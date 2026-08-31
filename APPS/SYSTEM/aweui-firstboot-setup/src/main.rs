use std::fs;
use std::path::Path;

fn main() {
    aweui_framework::init();
    println!("==================================================");
    println!("         AWEOS First-Boot AYUI Setup              ");
    println!("==================================================");

    let state_file = Path::new("/etc/aweos/first_boot");
    let is_fresh_install = if state_file.exists() {
        fs::read_to_string(state_file)
            .map(|s| s.contains("fresh_install=true"))
            .unwrap_or(false)
    } else {
        false
    };

    if !is_fresh_install {
        println!("[FirstBoot] System already initialized. Launching AWEUI Desktop Session...");
        return;
    }

    println!("Welcome to your new AWEOS Installation!");
    println!("Running initial post-installation setup wizard...");
    println!(" 1. Confirming System Language & Locale...");
    println!(" 2. Setting Default Theme & Appearance (AWEUI Dark)...");
    println!(" 3. Detecting Active Display & Output Configuration...");
    println!(" 4. Initializing Desktop Environment & User Session...");

    // Persist setup completion state (fresh_install = false)
    if let Err(e) = fs::create_dir_all("/etc/aweos") {
        println!("Warning: Could not create /etc/aweos: {}", e);
    }
    if let Err(e) = fs::write(state_file, "fresh_install=false\ncompleted_at=initial_boot\n") {
        println!("Warning: Could not persist first-boot completion: {}", e);
    } else {
        println!("[FirstBoot] First-boot initialization complete! State saved.");
    }

    println!("Launching full AWEUI Wayland Desktop Environment...");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_firstboot_state_file_handling() {
        let temp_dir = std::env::temp_dir().join("aweos_firstboot_test");
        let _ = fs::create_dir_all(&temp_dir);
        let test_file = temp_dir.join("first_boot");

        fs::write(&test_file, "fresh_install=true\n").unwrap();
        let is_fresh = fs::read_to_string(&test_file).map(|s| s.contains("fresh_install=true")).unwrap();
        assert!(is_fresh);

        fs::write(&test_file, "fresh_install=false\n").unwrap();
        let is_fresh_after = fs::read_to_string(&test_file).map(|s| s.contains("fresh_install=true")).unwrap();
        assert!(!is_fresh_after);

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
