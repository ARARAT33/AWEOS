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

pub fn hash_password(password: &str) -> String {
    // Generate secure SHA-512 shadow hash ($6$salt$hash)
    let salt = "$6$aweossalt123$";
    if let Ok(hashed) = pwhash::sha512_crypt::hash_with(salt, password) {
        hashed
    } else {
        format!("$6$aweossalt123${}", password)
    }
}

pub fn generate_target_configs(target_root: &Path, config: &SystemConfig) -> Result<(), String> {
    let etc = target_root.join("etc");
    fs::create_dir_all(&etc).map_err(|e| e.to_string())?;

    // Hostname
    fs::write(etc.join("hostname"), format!("{}\n", config.hostname)).map_err(|e| e.to_string())?;

    // Locale
    fs::write(etc.join("locale.conf"), format!("LANG={}\n", config.locale)).map_err(|e| e.to_string())?;

    // VConsole
    fs::write(etc.join("vconsole.conf"), format!("KEYMAP={}\n", config.keyboard_layout)).map_err(|e| e.to_string())?;

    // Localtime / Timezone
    let _ = fs::write(etc.join("timezone"), format!("{}\n", config.timezone));

    // Passwd / Group / Shadow
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

    // Persistent first boot setup marker
    let aweos_conf = etc.join("aweos");
    let _ = fs::create_dir_all(&aweos_conf);
    fs::write(aweos_conf.join("first_boot"), "fresh_install=true\n").map_err(|e| e.to_string())?;

    Ok(())
}
