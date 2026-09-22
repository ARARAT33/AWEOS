use std::fs;
use std::path::Path;

pub struct SystemConfig {
    pub hostname: String,
    pub full_name: String,
    pub username: String,
    pub password_hash: String,
    pub locale: String,
    pub keyboard_layout: String,
    pub timezone: String,
}

pub fn hash_password(password: &str) -> Result<String, String> {
    if password.is_empty() {
        return Err("Password must not be empty.".to_string());
    }

    pwhash::sha512_crypt::hash(password)
        .map_err(|e| format!("Failed to hash password securely: {}", e))
}

pub fn generate_target_configs(target_root: &Path, config: &SystemConfig) -> Result<(), String> {
    if config.username.is_empty() || config.hostname.is_empty() {
        return Err("Username and hostname must not be empty.".to_string());
    }

    let etc = target_root.join("etc");
    fs::create_dir_all(&etc).map_err(|e| e.to_string())?;

    fs::write(etc.join("hostname"), format!("{}\n", config.hostname))
        .map_err(|e| e.to_string())?;
    fs::write(etc.join("locale.conf"), format!("LANG={}\n", config.locale))
        .map_err(|e| e.to_string())?;
    fs::write(etc.join("vconsole.conf"), format!("KEYMAP={}\n", config.keyboard_layout))
        .map_err(|e| e.to_string())?;
    fs::write(etc.join("timezone"), format!("{}\n", config.timezone))
        .map_err(|e| e.to_string())?;

    let fstab_content = "# AWEOS Filesystem Table\nLABEL=aweos-root / ext4 defaults,noatime 0 1\n";
    fs::write(etc.join("fstab"), fstab_content).map_err(|e| e.to_string())?;

    let passwd_entry = format!(
        "root:x:0:0:root:/root:/bin/sh\n{}:x:1000:1000:{}:/home/{}:/bin/sh\n",
        config.username, config.full_name, config.username
    );
    fs::write(etc.join("passwd"), passwd_entry).map_err(|e| e.to_string())?;

    let group_entry = format!(
        "root:x:0:\nwheel:x:10:root,{}\n{}:x:1000:\n",
        config.username, config.username
    );
    fs::write(etc.join("group"), group_entry).map_err(|e| e.to_string())?;

    let shadow_entry = format!(
        "root:*:19000:0:99999:7:::\n{}:{}:19000:0:99999:7:::\n",
        config.username, config.password_hash
    );
    fs::write(etc.join("shadow"), shadow_entry).map_err(|e| e.to_string())?;

    let aweos_conf = etc.join("aweos");
    fs::create_dir_all(&aweos_conf).map_err(|e| e.to_string())?;
    fs::write(aweos_conf.join("first_boot"), "fresh_install=true\n")
        .map_err(|e| e.to_string())?;

    Ok(())
}
