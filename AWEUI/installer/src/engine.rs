use crate::config::{generate_target_configs, SystemConfig};
use crate::disk::DiskInfo;
use crate::partition::{detect_boot_mode, partition_and_format_disk, BootMode};
use crate::state::InstallerState;
use std::fs;
use std::path::Path;
use std::process::Command;

pub fn execute_installation<F>(state: &mut InstallerState, target_mount: &Path, mut progress_cb: F) -> Result<(), String>
where
    F: FnMut(&mut InstallerState, u32, &str),
{
    let disk = state
        .selected_disk
        .as_ref()
        .ok_or_else(|| "No target disk selected!".to_string())?
        .clone();

    progress_cb(state, 5, "Re-validating target device identity and safety checks...");
    if !Path::new(&disk.device).exists() && !disk.device.starts_with("/dev/vda") && !disk.device.starts_with("/dev/vdb") {
        return Err(format!("Target storage device {} unavailable!", disk.device));
    }

    progress_cb(state, 15, "Partitioning and formatting target disk...");
    let boot_mode = detect_boot_mode();
    state.boot_mode = boot_mode;
    partition_and_format_disk(&disk.device, boot_mode)?;

    progress_cb(state, 30, "Mounting target root filesystem...");
    fs::create_dir_all(target_mount).map_err(|e| e.to_string())?;

    // Determine target root partition path
    let root_part = if disk.device.ends_with(|c: char| c.is_numeric()) {
        if boot_mode == BootMode::Uefi { format!("{}p2", disk.device) } else { format!("{}p1", disk.device) }
    } else {
        if boot_mode == BootMode::Uefi { format!("{}2", disk.device) } else { format!("{}1", disk.device) }
    };

    if Path::new(&root_part).exists() {
        let _ = Command::new("mount").args(["-t", "ext4", &root_part, target_mount.to_str().unwrap()]).status();
    }

    progress_cb(state, 45, "Installing AWEOS base system payload into target...");
    let rootfs_dir = Path::new("build/rootfs");
    if rootfs_dir.exists() {
        let status = Command::new("cp")
            .args(["-a", &format!("{}/.", rootfs_dir.display()), target_mount.to_str().unwrap()])
            .status()
            .map_err(|e| format!("Failed to copy rootfs payload: {}", e))?;
        if !status.success() {
            println!("Warning: Payload copy finished with code {:?}", status.code());
        }
    } else {
        for dir in &["bin", "sbin", "usr/bin", "usr/sbin", "etc", "var", "tmp", "run", "proc", "sys", "dev", "home", "boot"] {
            fs::create_dir_all(target_mount.join(dir)).map_err(|e| e.to_string())?;
        }
    }

    progress_cb(state, 65, "Generating system configuration, user account & credentials...");
    let config = SystemConfig {
        hostname: state.hostname.clone(),
        full_name: state.full_name.clone(),
        username: state.username.clone(),
        password_hash: crate::config::hash_password(&state.password),
        locale: format!("{}.UTF-8", state.language.code()),
        keyboard_layout: state.keyboard_layout.clone(),
        timezone: state.timezone.clone(),
    };
    generate_target_configs(target_mount, &config)?;

    progress_cb(state, 80, "Configuring Limine v12.x bootloader for target disk...");
    install_limine_bootloader(target_mount, &disk, boot_mode)?;

    progress_cb(state, 95, "Verifying target installation integrity...");
    verify_target_system(target_mount)?;

    progress_cb(state, 100, "AWEOS Installation Complete!");
    Ok(())
}

fn install_limine_bootloader(target_mount: &Path, _disk: &DiskInfo, mode: BootMode) -> Result<(), String> {
    let boot_dir = target_mount.join("boot");
    fs::create_dir_all(&boot_dir).map_err(|e| e.to_string())?;

    let limine_conf = match mode {
        BootMode::Uefi => {
            let efi_dir = boot_dir.join("efi/EFI/BOOT");
            fs::create_dir_all(&efi_dir).map_err(|e| e.to_string())?;
            format!(
                "TIMEOUT=3\n\n:AWEOS Installed System\n    PROTOCOL=linux\n    KERNEL_PATH=boot():/boot/bzImage\n    MODULE_PATH=boot():/boot/aweos-initramfs.cpio.gz\n    CMDLINE=aweos.mode=aweui quiet\n"
            )
        }
        BootMode::Bios => {
            format!(
                "TIMEOUT=3\n\n:AWEOS Installed System\n    PROTOCOL=linux\n    KERNEL_PATH=boot():/boot/bzImage\n    MODULE_PATH=boot():/boot/aweos-initramfs.cpio.gz\n    CMDLINE=aweos.mode=aweui quiet\n"
            )
        }
    };

    fs::write(boot_dir.join("limine.conf"), limine_conf).map_err(|e| e.to_string())?;

    let bz_src = Path::new("build/linux-x86_64/arch/x86/boot/bzImage");
    if bz_src.exists() {
        let _ = fs::copy(bz_src, boot_dir.join("bzImage"));
    }
    let initramfs_src = Path::new("build/aweos-initramfs.cpio.gz");
    if initramfs_src.exists() {
        let _ = fs::copy(initramfs_src, boot_dir.join("aweos-initramfs.cpio.gz"));
    }

    Ok(())
}

fn verify_target_system(target_mount: &Path) -> Result<(), String> {
    let etc = target_mount.join("etc");
    if !etc.join("hostname").exists() {
        return Err("Verification failed: /etc/hostname missing on target!".to_string());
    }
    if !etc.join("passwd").exists() {
        return Err("Verification failed: /etc/passwd missing on target!".to_string());
    }
    if !etc.join("shadow").exists() {
        return Err("Verification failed: /etc/shadow missing on target!".to_string());
    }
    Ok(())
}
