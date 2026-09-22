use std::fs;
use std::path::Path;
use std::process::Command;

const DEFAULT_AWEUI_CONFIG: &str = r#"[desktop]
wallpaper = "/usr/share/backgrounds/aweos-default.png"
theme = "AWEUI-Dark"
icon_theme = "AWEUI-Icons"
font = "Sans"
font_size = 10
accent_color = "#3b82f6"

[input]
repeat_rate = 25
repeat_delay = 200
tap_to_click = true
pointer_speed = 1.0

[wm]
default_mode = "floating"
gap_size = 6
border_width = 2
active_border_color = "#3b82f6"
inactive_border_color = "#334155"
workspace_count = 4

[panel]
position = "top"
height = 32
auto_hide = false
widgets = ["launcher", "workspaces", "window_title", "cpu_ram", "clock", "control_center_toggle"]
"#;

fn detect_display() -> String {
    if let Ok(modes) = fs::read_dir("/sys/class/drm") {
        let mut found = Vec::new();
        for entry in modes.flatten() {
            let modes_path = entry.path().join("modes");
            if let Ok(contents) = fs::read_to_string(modes_path) {
                if let Some(mode) = contents.lines().find(|line| !line.trim().is_empty()) {
                    found.push(format!("{}:{}", entry.file_name().to_string_lossy(), mode.trim()));
                }
            }
        }
        if !found.is_empty() {
            return found.join(", ");
        }
    }

    if let Ok(size) = fs::read_to_string("/sys/class/graphics/fb0/virtual_size") {
        return format!("fb0:{}", size.trim().replace(',', "x"));
    }

    "unknown".to_string()
}

fn main() {
    aweui_framework::init();
    println!("==================================================");
    println!("         AWEOS First-Boot AWEUI Setup             ");
    println!("==================================================");

    let state_file = Path::new("/etc/aweos/first_boot");
    let is_fresh_install = fs::read_to_string(state_file)
        .map(|s| s.lines().any(|line| line.trim() == "fresh_install=true"))
        .unwrap_or(false);

    if !is_fresh_install {
        println!("[FirstBoot] System is already initialized.");
        return;
    }

    let locale = fs::read_to_string("/etc/locale.conf")
        .ok()
        .and_then(|s| s.lines().find(|line| line.starts_with("LANG=")).map(str::to_owned))
        .unwrap_or_else(|| "LANG=en_US.UTF-8".to_string());

    println!("Welcome to your new AWEOS Installation!");
    println!("Applying first-boot configuration...");
    println!(" 1. System locale: {}", locale);
    println!(" 2. Default theme: AWEUI-Dark");
    println!(" 3. Display: {}", detect_display());
    println!(" 4. Preparing AWEUI user session...");

    let config_dir = Path::new("/etc/aweui");
    if let Err(e) = fs::create_dir_all(config_dir) {
        eprintln!("[FirstBoot] Cannot create {}: {}", config_dir.display(), e);
        std::process::exit(1);
    }

    if let Err(e) = fs::write(config_dir.join("config.toml"), DEFAULT_AWEUI_CONFIG) {
        eprintln!("[FirstBoot] Cannot write AWEUI configuration: {}", e);
        std::process::exit(1);
    }

    if let Err(e) = fs::write(state_file, "fresh_install=false\n") {
        eprintln!("[FirstBoot] Cannot persist first-boot state: {}", e);
        std::process::exit(1);
    }

    println!("[FirstBoot] Configuration applied and first-boot state completed.");

    // The init system owns compositor startup. This program only performs one-time setup.
    if Path::new("/usr/bin/aweui").exists() {
        let _ = Command::new("/usr/bin/aweui").arg("--version").status();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_firstboot_state_file_handling() {
        let temp_dir = std::env::temp_dir().join(format!("aweos_firstboot_test_{}", std::process::id()));
        let _ = fs::create_dir_all(&temp_dir);
        let test_file = temp_dir.join("first_boot");

        fs::write(&test_file, "fresh_install=true\n").unwrap();
        let is_fresh = fs::read_to_string(&test_file)
            .unwrap()
            .lines()
            .any(|line| line.trim() == "fresh_install=true");
        assert!(is_fresh);

        fs::write(&test_file, "fresh_install=false\n").unwrap();
        let is_fresh_after = fs::read_to_string(&test_file)
            .unwrap()
            .lines()
            .any(|line| line.trim() == "fresh_install=true");
        assert!(!is_fresh_after);

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_default_config_matches_aweui_schema() {
        assert!(DEFAULT_AWEUI_CONFIG.contains("[desktop]"));
        assert!(DEFAULT_AWEUI_CONFIG.contains("font ="));
        assert!(DEFAULT_AWEUI_CONFIG.contains("[input]"));
        assert!(DEFAULT_AWEUI_CONFIG.contains("[wm]"));
        assert!(DEFAULT_AWEUI_CONFIG.contains("[panel]"));
        assert!(DEFAULT_AWEUI_CONFIG.contains("font_size = 10"));
    }
}
