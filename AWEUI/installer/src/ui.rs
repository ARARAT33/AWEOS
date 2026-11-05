use crate::i18n::I18n;
use crate::state::{InstallerState, InstallerStep};

pub fn render_screen(state: &InstallerState, i18n: &I18n) -> String {
    let mut out = String::new();

    out.push_str("\n┌──────────────────────────────────────────────────────────────────────────────────────┐\n");
    out.push_str("│                             AWEOS GRAPHICAL INSTALLER UI                            │\n");
    out.push_str("└──────────────────────────────────────────────────────────────────────────────────────┘\n");

    out.push_str(&render_sidebar(state));
    out.push_str("├──────────────────────────────────────────────────────────────────────────────────────┤\n");

    match &state.current_step {
        InstallerStep::Welcome => {
            out.push_str("  [ WELCOME TO AWEOS ]\n\n");
            out.push_str(&format!("  {}\n", i18n.t("welcome_title")));
            out.push_str(&format!("  {}\n\n", i18n.t("welcome_subtitle")));
            out.push_str("  Card: AWEOS Graphical Architecture Features\n");
            out.push_str("   * Pure Native Rust Wayland Compositor (AWEUI)\n");
            out.push_str("   * Built-in System Applications & Modular Panel Desktop\n");
            out.push_str("   * Transactional Package Manager (AOSIN) & Limine v12 Bootloader\n\n");
            out.push_str(&format!("  Actions: [1] {}   [Q] Quit\n", i18n.t("continue")));
        }
        InstallerStep::Language => {
            out.push_str("  [ SELECT LANGUAGE ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("select_language")));
            out.push_str(&format!("  Current Language: {}\n\n", state.language.name()));
            out.push_str("  Options:\n");
            out.push_str("   1. English (EN)\n");
            out.push_str("   2. Հայերեն (Armenian) (HY)\n");
            out.push_str("   3. Русский (Russian) (RU)\n\n");
            out.push_str(&format!("  Actions: [1-3] Select   [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::Keyboard => {
            out.push_str("  [ KEYBOARD SELECTION ]\n\n");
            out.push_str(&format!("  {}\n", i18n.t("keyboard_title")));
            out.push_str(&format!("  {}\n\n", i18n.t("keyboard_subtitle")));
            out.push_str(&format!("  Selected Layout: {}\n", state.keyboard_layout));
            out.push_str(&format!("  Selected Variant: {}\n\n", if state.keyboard_variant.is_empty() { "default" } else { &state.keyboard_variant }));
            out.push_str(&format!("  Test Input Box: [ {} ]\n\n", i18n.t("test_keyboard")));
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::Network => {
            out.push_str("  [ NETWORK CONFIGURATION ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("network_title")));
            if state.network_connected {
                out.push_str("  Status: Connected (Interface: eth0, IP: 192.168.122.15)\n\n");
            } else {
                out.push_str(&format!("  Status: {}\n\n", i18n.t("network_offline")));
            }
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::InstallationType => {
            out.push_str("  [ INSTALLATION TYPE — SAFETY HOLD ]\n\n");
            out.push_str("  Disk installation is currently DISABLED.\n");
            out.push_str("  The former flow repartitioned and formatted the whole selected disk.\n");
            out.push_str("  A tested data-preserving backup and rollback backend is not ready.\n");
            out.push_str("  [DISABLED] Erase entire disk\n");
            out.push_str("  [NOT IMPLEMENTED] Custom partition / preserve existing OS\n\n");
            out.push_str("  No disk will be modified by this installer build.\n\n");
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::DiskSelection => {
            out.push_str("  [ TARGET DISK INFORMATION ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("select_disk_title")));
            if let Some(disk) = &state.selected_disk {
                out.push_str(&format!("  Selected Target Disk: {} - {} ({:.1} GB)\n\n", disk.device, disk.model, disk.size_gb));
            } else {
                out.push_str("  No target disk is selected.\n\n");
            }
            out.push_str("  Device discovery is informational only; no disk is auto-selected.\n");
            out.push_str("  Disk installation remains disabled and this screen cannot authorize writes.\n\n");
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::Partitioning => {
            out.push_str("  [ PARTITION PLAN — PREVIEW ONLY ]\n\n");
            out.push_str("  Firmware mode is not used while disk installation is disabled.\n");
            if let Some(disk) = &state.selected_disk {
                out.push_str(&format!("  Informational Device: {} ({:.1} GB)\n", disk.device, disk.size_gb));
            } else {
                out.push_str("  No target device selected.\n");
            }
            out.push_str("\n  No partition table will be written and no filesystem will be formatted.\n");
            out.push_str("  Data-preserving partition selection and rollback are not implemented.\n\n");
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::UserAccount => {
            out.push_str("  [ USER ACCOUNT CREATION ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("user_account_title")));
            out.push_str(&format!("   Full Name:     [ {} ]\n", state.full_name));
            out.push_str(&format!("   Username:      [ {} ]\n", state.username));
            out.push_str(&format!("   Hostname:      [ {} ]\n", state.hostname));
            let password_display = if state.password.is_empty() { "(not set)".to_string() } else { "*".repeat(state.password.len()) };
            let confirm_display = if state.password_confirm.is_empty() { "(not set)".to_string() } else { "*".repeat(state.password_confirm.len()) };
            out.push_str(&format!("   Password:      [ {} ]\n", password_display));
            out.push_str(&format!("   Confirm Pass:  [ {} ]\n\n", confirm_display));
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::Timezone => {
            out.push_str("  [ TIMEZONE & REGION ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("timezone_title")));
            out.push_str(&format!("   Selected Region/Timezone: [ {} ]\n\n", state.timezone));
            out.push_str(&format!("  Actions: [C] {}   [B] {}\n", i18n.t("continue"), i18n.t("back")));
        }
        InstallerStep::Summary => {
            out.push_str("  [ INSTALLATION SUMMARY — NOT EXECUTABLE ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("summary_title")));
            out.push_str(&format!("   Language: {}\n", state.language.name()));
            out.push_str(&format!("   Keyboard: {}\n", state.keyboard_layout));
            out.push_str(&format!("   Target Disk: {}\n", state.selected_disk.as_ref().map(|d| d.device.as_str()).unwrap_or("Not selected")));
            out.push_str(&format!("   User: {} ({})\n", state.username, state.full_name));
            out.push_str(&format!("   Hostname: {}\n", state.hostname));
            out.push_str(&format!("   Timezone: {}\n\n", state.timezone));
            out.push_str("  DISK INSTALLATION IS DISABLED FOR DATA SAFETY.\n");
            out.push_str("  The old implementation erased/reformatted the selected disk.\n");
            out.push_str("  A tested backup, staging, verification, and rollback path is not available.\n");
            out.push_str("  No disk, partition, filesystem, bootloader, or user data will be changed.\n\n");
            out.push_str("  Actions: [I] Unavailable   [B] Back\n");
        }
        InstallerStep::Installing => {
            out.push_str("  [ INSTALLATION IN PROGRESS ]\n\n");
            out.push_str(&format!("  {}\n\n", i18n.t("installing_title")));
            out.push_str(&format!("  Current Operation: {}\n", state.current_operation));
            out.push_str(&format!("  Progress: [{}{}] {}%\n\n", "=".repeat((state.progress_percent / 5) as usize), " ".repeat(20 - (state.progress_percent / 5) as usize), state.progress_percent));
        }
        InstallerStep::Complete => {
            out.push_str("  [ INSTALLATION COMPLETE ]\n\n");
            out.push_str("  No disk installation is enabled in this build.\n");
            out.push_str("  This screen must not be used to claim that a target disk was installed.\n\n");
            out.push_str(&format!("  Actions: [R] {}\n", i18n.t("reboot")));
        }
        InstallerStep::Error(err) => {
            out.push_str("  [ INSTALLATION ERROR ]\n\n");
            out.push_str(&format!("  Error: {}\n\n", err));
            out.push_str("  Actions: [B] Return to Safety\n");
        }
    }

    out.push_str("└──────────────────────────────────────────────────────────────────────────────────────┘\n");
    out
}

fn render_sidebar(state: &InstallerState) -> String {
    let steps = vec![
        ("Welcome", &InstallerStep::Welcome),
        ("Language", &InstallerStep::Language),
        ("Keyboard", &InstallerStep::Keyboard),
        ("Network", &InstallerStep::Network),
        ("Type", &InstallerStep::InstallationType),
        ("Disk", &InstallerStep::DiskSelection),
        ("Partition", &InstallerStep::Partitioning),
        ("User", &InstallerStep::UserAccount),
        ("Timezone", &InstallerStep::Timezone),
        ("Summary", &InstallerStep::Summary),
        ("Install", &InstallerStep::Installing),
        ("Complete", &InstallerStep::Complete),
    ];

    let mut line = String::from("  Steps: ");
    for (name, step) in steps {
        if std::mem::discriminant(&state.current_step) == std::mem::discriminant(step) {
            line.push_str(&format!(" [-> {} <-] ", name));
        } else {
            line.push_str(&format!("  {}  ", name));
        }
    }
    line.push('\n');
    line
}
