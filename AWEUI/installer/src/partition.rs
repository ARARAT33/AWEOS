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
        stdin.write_all(script.as_bytes())
            .map_err(|e| format!("Failed to provide partition table to sfdisk: {}", e))?;
    }

    let status = child.wait().map_err(|e| format!("Failed waiting for sfdisk: {}", e))?;
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

fn partition_path(target_dev: &str, number: u8) -> String {
    if target_dev.ends_with(|c: char| c.is_numeric()) {
        format!("{}p{}", target_dev, number)
    } else {
        format!("{}{}", target_dev, number)
    }
}

pub fn partition_and_format_disk(target_dev: &str, mode: BootMode) -> Result<(), String> {
    println!("Partitioning disk {} in {:?} mode...", target_dev, mode);

    let meta = std::fs::metadata(target_dev)
        .map_err(|e| format!("Cannot inspect target block device {}: {}", target_dev, e))?;
    if !std::os::unix::fs::FileTypeExt::is_block_device(&meta.file_type()) {
        return Err(format!(
            "Target {} is not a block device; refusing simulated partitioning.",
            target_dev
        ));
    }

    match mode {
        BootMode::Uefi => {
            let sfdisk_script =
                "label: gpt\nsize=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n, type=0FC63DA1-8483-4772-8E79-3D69D8477DE4\n";
            run_sfdisk(target_dev, sfdisk_script)?;

            let esp = partition_path(target_dev, 1);
            let root = partition_path(target_dev, 2);

            run_checked(
                "mkfs.vfat",
                &["-F32".to_string(), "-n".to_string(), "AWEOS-ESP".to_string(), esp],
                "formatting the EFI System Partition",
            )?;
            run_checked(
                "mke2fs",
                &["-t".to_string(), "ext4".to_string(), "-F".to_string(), "-L".to_string(), "aweos-root".to_string(), root],
                "formatting the AWEOS root partition",
            )?;
        }
        BootMode::Bios => {
            let sfdisk_script = "label: dos\n, type=83, bootable\n";
            run_sfdisk(target_dev, sfdisk_script)?;

            let root = partition_path(target_dev, 1);
            run_checked(
                "mke2fs",
                &["-t".to_string(), "ext4".to_string(), "-F".to_string(), "-L".to_string(), "aweos-root".to_string(), root],
                "formatting the AWEOS root partition",
            )?;
        }
    }

    Ok(())
}
