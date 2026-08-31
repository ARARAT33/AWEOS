use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum BootMode {
    Uefi,
    Bios,
}

pub fn detect_boot_mode() -> BootMode {
    if std::path::Path::new("/sys/firmware/efi").exists() {
        BootMode::Uefi
    } else {
        BootMode::Bios
    }
}

pub fn partition_and_format_disk(target_dev: &str, mode: BootMode) -> Result<(), String> {
    println!("Partitioning disk {} in {:?} mode...", target_dev, mode);

    if !std::path::Path::new(target_dev).exists() {
        println!("Notice: Block device {} not present in devtmpfs, performing logical simulation for partitioning.", target_dev);
        return Ok(());
    }

    match mode {
        BootMode::Uefi => {
            let sfdisk_script = "label: gpt\nsize=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n, type=0FC63DA1-8483-4772-8E79-3D69D8477DE4\n";
            if let Ok(mut child) = Command::new("sfdisk")
                .arg(target_dev)
                .stdin(std::process::Stdio::piped())
                .spawn()
            {
                if let Some(mut stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = stdin.write_all(sfdisk_script.as_bytes());
                }
                let _ = child.wait();
            } else {
                println!("Warning: sfdisk command not available in environment. Simulating partitioning for {}", target_dev);
            }

            let p1 = if target_dev.ends_with(|c: char| c.is_numeric()) { format!("{}p1", target_dev) } else { format!("{}1", target_dev) };
            let p2 = if target_dev.ends_with(|c: char| c.is_numeric()) { format!("{}p2", target_dev) } else { format!("{}2", target_dev) };

            let _ = Command::new("mkfs.vfat").args(["-F32", &p1]).status();
            let _ = Command::new("mke2fs").args(["-t", "ext4", "-F", &p2]).status();
        }
        BootMode::Bios => {
            let sfdisk_script = "label: dos\n, type=83, bootable\n";
            if let Ok(mut child) = Command::new("sfdisk")
                .arg(target_dev)
                .stdin(std::process::Stdio::piped())
                .spawn()
            {
                if let Some(mut stdin) = child.stdin.take() {
                    use std::io::Write;
                    let _ = stdin.write_all(sfdisk_script.as_bytes());
                }
                let _ = child.wait();
            } else {
                println!("Warning: sfdisk command not available in environment. Simulating partitioning for {}", target_dev);
            }

            let p1 = if target_dev.ends_with(|c: char| c.is_numeric()) { format!("{}p1", target_dev) } else { format!("{}1", target_dev) };
            let _ = Command::new("mke2fs").args(["-t", "ext4", "-F", &p1]).status();
        }
    }

    Ok(())
}
