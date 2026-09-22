use crate::config::{generate_target_configs, hash_password, SystemConfig};
use crate::disk::DiskInfo;
use crate::partition::{detect_boot_mode, partition_and_format_disk, BootMode};
use crate::state::InstallerState;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn source_path(name: &str) -> Option<PathBuf> {
    let packaged = Path::new("/boot").join(name);
    if packaged.exists() {
        return Some(packaged);
    }

    let local = Path::new("build").join(name);
    if local.exists() {
        return Some(local);
    }

    let loader = Path::new("Bootloader/x86_64").join(name);
    loader.exists().then_some(loader)
}

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
    if !Path::new(&disk.device).is_block_device() {
        return Err(format!(
            "Target storage device {} is not a real block device; refusing installation.",
            disk.device
        ));
    }

    if state.username.trim().is_empty() || state.hostname.trim().is_empty() {
        return Err("Username and hostname must not be empty.".to_string());
    }

    let password_hash = hash_password(&state.password)?;

    progress_cb(state, 15, "Partitioning and formatting target disk...");
    let boot_mode = detect_boot_mode();
    state.boot_mode = boot_mode;
    partition_and_format_disk(&disk.device, boot_mode)?;

    progress_cb(state, 30, "Mounting target root filesystem...");
    fs::create_dir_all(target_mount).map_err(|e| e.to_string())?;

    let root_part = if disk.device.ends_with(|c: char| c.is_numeric()) {
        if boot_mode == BootMode::Uefi { format!("{}p2", disk.device) } else { format!("{}p1", disk.device) }
    } else if boot_mode == BootMode::Uefi {
        format!("{}2", disk.device)
    } else {
        format!("{}1", disk.device)
    };

    if !Path::new(&root_part).is_block_device() {
        return Err(format!("Expected formatted root partition {} was not created.", root_part));
    }

    let mount_status = Command::new("mount")
        .args(["-t", "ext4", &root_part, target_mount.to_str().unwrap()])
        .status()
        .map_err(|e| format!("Mount command failed: {}", e))?;
    if !mount_status.success() {
        return Err(format!("Failed to mount target partition {} at {}", root_part, target_mount.display()));
    }

    progress_cb(state, 45, "Installing AWEOS base system payload into target...");
    let rootfs_dir = Path::new("build/rootfs");
    if !rootfs_dir.is_dir() {
        return Err("AWEOS rootfs payload is missing; refusing to create a simulated installation.".to_string());
    }

    let status = Command::new("cp")
        .args(["-a", &format!("{}/.", rootfs_dir.display()), target_mount.to_str().unwrap()])
        .status()
        .map_err(|e| format!("Failed to copy rootfs payload: {}", e))?;
    if !status.success() {
        return Err("Failed to copy AWEOS rootfs payload.".to_string());
    }

    progress_cb(state, 65, "Generating system configuration, user account & credentials...");
    let config = SystemConfig {
        hostname: state.hostname.clone(),
        full_name: state.full_name.clone(),
        username: state.username.clone(),
        password_hash,
        locale: format!("{}.UTF-8", state.language.code()),
        keyboard_layout: state.keyboard_layout.clone(),
        timezone: state.timezone.clone(),
    };
    generate_target_configs(target_mount, &config)?;

    let packaged_kernel = source_path("bzImage").ok_or_else(|| "Packaged AWEOS kernel bzImage is missing.".to_string())?;
    let packaged_initramfs = source_path("aweos-initramfs.cpio.gz").ok_or_else(|| "Packaged AWEOS initramfs is missing.".to_string())?;
    let packaged_efi = source_path("BOOTX64.EFI").ok_or_else(|| "Packaged UEFI bootloader BOOTX64.EFI is missing.".to_string())?;
    let packaged_limine = source_path("limine-bios.sys").ok_or_else(|| "Packaged Limine BIOS payload is missing.".to_string())?;

    progress_cb(state, 80, "Installing AWEOS boot payload...");
    install_limine_bootloader(target_mount, &disk, boot_mode, &packaged_kernel, &packaged_initramfs, &packaged_efi, &packaged_limine)?;

    progress_cb(state, 95, "Verifying target installation integrity...");
    verify_target_system(target_mount)?;

    progress_cb(state, 98, "Cleaning up and unmounting target filesystem...");
    let _ = Command::new("sync").status();
    let _ = Command::new("umount").arg(target_mount.to_str().unwrap()).status();

    progress_cb(state, 100, "AWEOS Installation Complete!");
    Ok(())
}

fn install_limine_bootloader(
    target_mount: &Path,
    disk: &DiskInfo,
    mode: BootMode,
    kernel: &Path,
    initramfs: &Path,
    efi: &Path,
    limine_bios: &Path,
) -> Result<(), String> {
    let boot_dir = target_mount.join("boot");
    fs::create_dir_all(&boot_dir).map_err(|e| e.to_string())?;
    fs::copy(kernel, boot_dir.join("bzImage")).map_err(|e| format!("Failed to install kernel: {}", e))?;
    fs::copy(initramfs, boot_dir.join("aweos-initramfs.cpio.gz")).map_err(|e| format!("Failed to install initramfs: {}", e))?;
    fs::copy(limine_bios, boot_dir.join("limine-bios.sys")).map_err(|e| format!("Failed to install Limine BIOS payload: {}", e))?;

    let conf = "TIMEOUT=3\n\n:AWEOS Installed System\n    PROTOCOL=linux\n    KERNEL_PATH=boot():/boot/bzImage\n    MODULE_PATH=boot():/boot/aweos-initramfs.cpio.gz\n    CMDLINE=aweos.mode=aweui console=tty0 console=ttyS0,115200n8\n";
    fs::write(boot_dir.join("limine.conf"), conf).map_err(|e| e.to_string())?;

    match mode {
        BootMode::Uefi => {
            let efi_dir = target_mount.join("boot/efi/EFI/BOOT");
            fs::create_dir_all(&efi_dir).map_err(|e| e.to_string())?;
            fs::copy(efi, efi_dir.join("BOOTX64.EFI"))
                .map_err(|e| format!("Failed to install UEFI bootloader: {}", e))?;
        }
        BootMode::Bios => {
            let status = Command::new("limine")
                .args(["bios-install", &disk.device])
                .status()
                .map_err(|e| format!("Failed to start Limine BIOS installer: {}", e))?;
            if !status.success() {
                return Err(format!("Limine BIOS installation failed for {}", disk.device));
            }
        }
    }

    Ok(())
}

fn verify_target_system(target_mount: &Path) -> Result<(), String> {
    let required = [
        "etc/hostname",
        "etc/passwd",
        "etc/shadow",
        "etc/fstab",
        "boot/bzImage",
        "boot/aweos-initramfs.cpio.gz",
        "boot/limine.conf",
        "sbin/init",
    ];

    for rel in required {
        if !target_mount.join(rel).exists() {
            return Err(format!("Verification failed: {} missing on target!", rel));
        }
    }

    Ok(())
}
