use crate::state::InstallerState;
use std::path::Path;

/// Disk installation is intentionally unavailable until AWEOS has a tested,
/// data-preserving staging, backup, deployment, verification, and rollback
/// transaction. Do not re-enable the old whole-disk formatter as a shortcut.
pub const INSTALLATION_DISABLED_REASON: &str =
    "AWEOS disk installation is disabled for data safety: the current implementation does not provide a tested data-preserving staging, backup, deployment, verification, and rollback transaction. No disk, partition, filesystem, bootloader, or user data was modified.";

pub fn execute_installation<F>(
    _state: &mut InstallerState,
    _target_mount: &Path,
    _progress_cb: F,
) -> Result<(), String>
where
    F: FnMut(&mut InstallerState, u32, &str),
{
    Err(INSTALLATION_DISABLED_REASON.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::disk::DiskInfo;
    use crate::state::InstallerState;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn installer_refuses_before_callbacks_or_target_path_creation() {
        let mut state = InstallerState::default();
        state.selected_disk = Some(DiskInfo {
            device: "/dev/null".to_string(),
            name: "null".to_string(),
            model: "test-only character device".to_string(),
            size_bytes: 0,
            size_gb: 0.0,
            is_removable: false,
            partitions: Vec::new(),
        });

        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock must be after UNIX epoch")
            .as_nanos();
        let target = std::env::temp_dir().join(format!(
            "aweos-installer-must-not-create-target-{nonce}"
        ));
        assert!(!target.exists());

        let mut callbacks = 0;
        let result = execute_installation(&mut state, &target, |_state, _percent, _message| {
            callbacks += 1;
        });

        let error = result.expect_err("disk installation must remain disabled");
        assert!(error.contains("disabled for data safety"));
        assert!(error.contains("No disk"));
        assert_eq!(callbacks, 0, "a blocked install must not report progress");
        assert!(
            !target.exists(),
            "a blocked install must not create or mount a target directory"
        );
    }

    #[test]
    fn installer_refuses_even_when_no_target_is_selected() {
        let mut state = InstallerState::default();
        let target = std::env::temp_dir().join("aweos-installer-no-target-must-not-exist");
        let result = execute_installation(&mut state, &target, |_state, _percent, _message| {});
        assert!(result.unwrap_err().contains("disabled for data safety"));
        assert!(state.selected_disk.is_none());
    }
}
