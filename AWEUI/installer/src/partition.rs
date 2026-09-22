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

fn run_sfdisk(target_dev: &str, script: &str) -> Result<(), String> {
    use std::io::Write;

    let mut child = Command::new("sfdisk")
        .arg(target_dev)
        .stdin(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start sfdisk for {}: {}", target_dev, e))?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(script.as_bytes())
            .map_err(|e| format!("Failed to provide partition table to sfdisk: {}", e))?;
    }

    let status = child
        .wait()
        .map_err(|e| format!("Failed waiting for sfdisk: {}", e))?;

    if !status.success() {
        return Err(format!("sfdisk failed while partitioning {}", target_dev));
    }

    Ok(())
}

fn run_checked(command: &str, args: &[String], description: &str) -> Result<(), String> {
    let status = Command::new(command)
        .args(args)
        .status()
        .map_err(|e| format!("Failed to start {}: {}", description, e))?;

    if !status.success() {
        return Err(format!("{} failed with status {}", description, status));
    }

    Ok(())
}

pub fn partition_and_format_disk(target_dev: &str, mode: BootMode) -> Result<(), String> {
    println!("Partitioning disk {} in {:?} mode...", target_dev, mode);

    if !std::path::Path::new(target_dev).exists() {
        return Err(format!(
            "Target block device {} does not exist; refusing simulated partitioning.",
            target_dev
        ));
    }

    match mode {
        BootMode::Uefi => {
            let sfdisk_script =
                "label: gpt\nsize=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n, type=0FC63DA1-8483-4772-8E79-3D69D8477DE4\n";
            run_sfdisk(target_dev, sfdisk_script)?;

            let p1 = if target_dev.ends_with(|c: char| c.is_numeric()) {
                format!("{}p1", target_dev)
            } else {
                format!("{}1", target_dev)
            };
            let p2 = if target_dev.ends_with(|c: char| c.is_numeric()) {
                format!("{}p2", target_dev)
            } else {
                format!("{}2", target_dev)
            };

            run_checked(
                "mkfs.vfat",
                &["-F32".to_string(), p1],
                "mkfs.vfat",
            )?;
            run_checked(
                "mke2fs",
                &["-t".to_string(), "ext4".to_string(), "-F".to_string(), p2],
                "mke2fs",
            )?;
        }
        BootMode::Bios => {
            let sfdisk_script = "label: dos\n, type=83, bootable\n";
            run_sfdisk(target_dev, sfdisk_script)?;

            let p1 = if target_dev.ends_with(|c: char| c.is_numeric()) {
                format!("{}p1", target_dev)
            } else {
                format!("{}1", target_dev)
            };

            run_checked(
                "mke2fs",
                &["-t".to_string(), "ext4".to_string(), "-F".to_string(), p1],
                "mke2fs",
            )?;
        }
    }

    Ok(())
}
