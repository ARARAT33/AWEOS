use crate::disk::DiskInfo;
use crate::i18n::Language;
use crate::partition::BootMode;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum InstallerStep {
    Welcome,
    Language,
    Keyboard,
    Network,
    InstallationType,
    DiskSelection,
    Partitioning,
    UserAccount,
    Timezone,
    Summary,
    Installing,
    Complete,
    Error(String),
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct InstallerState {
    pub current_step: InstallerStep,
    pub language: Language,
    pub keyboard_layout: String,
    pub keyboard_variant: String,
    pub network_connected: bool,
    pub selected_disk: Option<DiskInfo>,
    pub boot_mode: BootMode,
    pub full_name: String,
    pub username: String,
    pub hostname: String,
    pub password: String,
    pub password_confirm: String,
    pub timezone: String,
    pub progress_percent: u32,
    pub current_operation: String,
}

impl Default for InstallerState {
    fn default() -> Self {
        Self {
            current_step: InstallerStep::Welcome,
            language: Language::English,
            keyboard_layout: "us".to_string(),
            keyboard_variant: "".to_string(),
            network_connected: false,
            selected_disk: None,
            boot_mode: BootMode::Bios,
            full_name: "AWEOS User".to_string(),
            username: "aweos".to_string(),
            hostname: "aweos-pc".to_string(),
            password: "aweos".to_string(),
            password_confirm: "aweos".to_string(),
            timezone: "UTC".to_string(),
            progress_percent: 0,
            current_operation: "Initializing...".to_string(),
        }
    }
}

impl InstallerState {
    pub fn next_step(&mut self) {
        self.current_step = match &self.current_step {
            InstallerStep::Welcome => InstallerStep::Language,
            InstallerStep::Language => InstallerStep::Keyboard,
            InstallerStep::Keyboard => InstallerStep::Network,
            InstallerStep::Network => InstallerStep::InstallationType,
            InstallerStep::InstallationType => InstallerStep::DiskSelection,
            InstallerStep::DiskSelection => InstallerStep::Partitioning,
            InstallerStep::Partitioning => InstallerStep::UserAccount,
            InstallerStep::UserAccount => InstallerStep::Timezone,
            InstallerStep::Timezone => InstallerStep::Summary,
            InstallerStep::Summary => InstallerStep::Installing,
            InstallerStep::Installing => InstallerStep::Complete,
            InstallerStep::Complete => InstallerStep::Complete,
            InstallerStep::Error(_) => InstallerStep::Welcome,
        };
    }

    pub fn prev_step(&mut self) {
        self.current_step = match &self.current_step {
            InstallerStep::Language => InstallerStep::Welcome,
            InstallerStep::Keyboard => InstallerStep::Language,
            InstallerStep::Network => InstallerStep::Keyboard,
            InstallerStep::InstallationType => InstallerStep::Network,
            InstallerStep::DiskSelection => InstallerStep::InstallationType,
            InstallerStep::Partitioning => InstallerStep::DiskSelection,
            InstallerStep::UserAccount => InstallerStep::Partitioning,
            InstallerStep::Timezone => InstallerStep::UserAccount,
            InstallerStep::Summary => InstallerStep::Timezone,
            _ => self.current_step.clone(),
        };
    }
}
