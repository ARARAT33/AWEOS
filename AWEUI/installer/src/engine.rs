use crate::config::{generate_target_configs, hash_password, SystemConfig};
use crate::disk::DiskInfo;
use crate::partition::{detect_boot_mode, partition_and_format_disk, BootMode};
use crate::state::InstallerState;
use std::fs;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn is_block_device(path: &Path) -> bool {
    fs::metadata(path)
        .map(|m| m.file_type().is_block_device())
        .unwrap_or(false)
}

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

fn partition_path(disk: &str, number: u8) -> String {
    if disk.ends_with(|c: char| c.is_numeric()) {
        format!("{}p{}", disk, number)
    } else {
        format!("{}{}", disk, number)
    }
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
    if !is_block_device(Path::new(&disk.device)) {
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

    let root_part = partition_path(&disk.device, if boot_mode == BootMode::Uefi { 2 } else { 1 });
    if !is_block_device(Path::new(&root_part)) {
        return Err(format!("Expected formatted root partition {} was not created.", root_part));
    }

    let root_mount = Command::new("mount")
        .args(["-t", "ext4", &root_part, target_mount.to_str().unwrap()])
        .status()
        .map_err(|e| format!("Mount command failed: {}", e))?;
    if !root_mount.success() {
        return Err(format!("Failed to mount target partition {} at {}", root_part, target_mount.display()));
    }

    let mut esp_mounted = false;
    if boot_mode == BootMode::Uefi {
        let esp_part = partition_path(&disk.device, 1);
        if !is_block_device(Path::new(&esp_part)) {
            let _ = Command::new("umount").arg(target_mount).status();
            return Err(format!("Expected EFI System Partition {} was not created.", esp_part));
        }

        let esp_dir = target_mount.join("boot/efi");
        if let Err(e) = fs::create_dir_all(&esp_dir) {
            let _ = Command::new("umount").arg(target_mount).status();
            return Err(format!("Failed to create EFI mountpoint {}: {}", esp_dir.display(), e));
        }

        let esp_status = Command::new("mount")
            .args(["-t", "vfat", &esp_part, esp_dir.to_str().unwrap()])
            .status()
            .map_err(|e| format!("EFI mount command failed: {}", e))?;
        if !esp_status.success() {
            let _ = Command::new("umount").arg(target_mount).status();
            return Err(format!("Failed to mount EFI System Partition {}.", esp_part));
        }
        esp_mounted = true;
    }

    let install_result = (|| -> Result<(), String> {
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
        install_limine_bootloader(
            target_mount,
            &disk,
            boot_mode,
            &packaged_kernel,
            &packaged_initramfs,
            &packaged_efi,
            &packaged_limine,
        )?;

        progress_cb(state, 95, "Verifying target installation integrity...");
        verify_target_system(target_mount, boot_mode)?;

        Ok(())
    })();

    if esp_mounted {
        let _ = Command::new("umount").arg(target_mount.join("boot/efi")).status();
    }
    let _ = Command::new("sync").status();
    let _ = Command::new("umount").arg(target_mount).status();

    install_result.map(|_| {
        progress_cb(state, 100, "AWEOS Installation Complete!");
    })
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

    let conf = "TIMEOUT=3\n\n:AWEOS Installed System\n    PROTOCOL=linux\n    KERNEL_PATH=boot():/boot/bzImage\n    MODULE_PATH=boot():/boot/aweos-initramfs.cpio.gz\n    CMDLINE=aweos.mode=aweui console=tty0 console=ttyS0,115200n8 quiet\n";
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

fn verify_target_system(target_mount: &Path, mode: BootMode) -> Result<(), String> {
    let required = [
        "etc/hostname",
        "etc/passwd",
        "etc/shadow",
        "etc/fstab",
        "boot/bzImage",
        "boot/aweos-initramfs.cpio.gz",
        "boot/limine.conf",
        "boot/limine-bios.sys",
        "sbin/init",
    ];

    for rel in required {
        if !target_mount.join(rel).exists() {
            return Err(format!("Verification failed: {} missing on target!", rel));
        }
    }

    if mode == BootMode::Uefi && !target_mount.join("boot/efi/EFI/BOOT/BOOTX64.EFI").exists() {
        return Err("Verification failed: UEFI BOOTX64.EFI missing from the mounted ESP.".to_string());
    }

    Ok(())
}
