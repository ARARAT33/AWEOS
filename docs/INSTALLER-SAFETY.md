# AWEOS installer safety status

## Current behavior

The Rust GUI installer is a preview only. It must not write to disks.

The previous implementation had two unsafe defaults:

- Startup silently selected the first discovered block device as the target.
- The installation engine rewrote the whole disk's partition table with
  `sfdisk`, created new filesystems with `mkfs.vfat` / `mke2fs`, and only
  then copied the root filesystem. It had no tested backup or rollback
  transaction for existing partitions and user data.

The old unattended `--auto` path could reach that flow when
`AWEOS_ALLOW_DESTRUCTIVE_INSTALL=1` was set. That environment variable is no
longer an authorization mechanism.

Current safeguards:

- No disk is selected automatically.
- The partition/format API returns an explicit error without running
  `sfdisk`, `mkfs`, `mount`, or any other disk command.
- The installation engine returns before invoking progress callbacks or
  creating the target mount path.
- The summary screen labels installation as unavailable and says no disk,
  partition, filesystem, bootloader, or user data will be changed.
- Pressing `I` cannot advance to installation; `--auto` exits with status 2.
- The default installer password and confirmation fields are empty.
- The C installer/updater transaction engine remains fail-closed as well.

## Requirements before enabling installation

Do not re-enable the Rust engine by restoring the former whole-disk formatter.
A production installation path must first implement and test all of the
following:

1. Explicit target selection by the user; never select the first disk.
2. Revalidation immediately before writes using block-device identity,
   capacity, major/minor numbers, and mount/use state.
3. A partition-preserving installation mode, or an explicitly separate
   whole-disk mode with a clear, typed, target-specific confirmation and a
   verified backup. A warning alone is insufficient.
4. A data-preservation plan that is completed and verified before destructive
   operations begin.
5. Staging on the target without replacing the currently bootable system.
6. Atomic boot-entry/bootloader publication and a recoverable previous entry.
7. Verification of installed files, boot assets, filesystem metadata, and
   bootability before commit.
8. Rollback that never deletes or overwrites files changed by the user after
   staging.
9. Cleanup/unmount handling on every error path, including process interruption.
10. Automated tests using disposable loop devices and virtual machines, plus
    manual BIOS/UEFI validation. Tests must never point at a developer's real
    system disk.

## Validation

The Rust workspace tests cover the fail-closed engine, disabled partition
operation, blank default credentials, non-advancing Summary state, and UI
disclosure. The userland workflow also runs the built `aweui-installer`
binary with the legacy destructive override set and verifies that `--auto`
still exits before any disk operation.

No installer capability or hardware support is claimed by these checks.
