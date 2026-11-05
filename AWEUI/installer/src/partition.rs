#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum BootMode {
    Uefi,
    Bios,
}

pub fn detect_boot_mode() -> BootMode {
    if std::path::Path::new("/sys/firmware/efi").is_dir() {
        BootMode::Uefi
    } else {
        BootMode::Bios
    }
}

/// Compatibility guard for callers of the former whole-disk formatter.
///
/// The old implementation rewrote the selected disk's partition table and
/// formatted new filesystems without a tested backup/rollback transaction.
/// Keep this API fail-closed so an accidental future call cannot erase data.
pub fn partition_and_format_disk(target_dev: &str, _mode: BootMode) -> Result<(), String> {
    Err(format!(
        "AWEOS disk partitioning is disabled for data safety (target: {}). No partition table or filesystem was changed.",
        target_dev
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whole_disk_partitioning_is_disabled_without_touching_target() {
        let result = partition_and_format_disk("/dev/null", BootMode::Bios);
        let error = result.expect_err("whole-disk formatting must fail closed");
        assert!(error.contains("disabled for data safety"));
        assert!(error.contains("No partition table or filesystem was changed"));
    }
}
