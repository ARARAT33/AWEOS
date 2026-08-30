use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AweuiConfig {
    pub desktop: DesktopConfig,
    pub input: InputConfig,
    pub wm: WmConfig,
    pub panel: PanelConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DesktopConfig {
    pub wallpaper: String,
    pub theme: String,
    pub icon_theme: String,
    pub font: String,
    pub font_size: u32,
    pub accent_color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InputConfig {
    pub repeat_rate: i32,
    pub repeat_delay: i32,
    pub tap_to_click: bool,
    pub pointer_speed: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WmConfig {
    pub default_mode: String,
    pub gap_size: u32,
    pub border_width: u32,
    pub active_border_color: String,
    pub inactive_border_color: String,
    pub workspace_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PanelConfig {
    pub position: String,
    pub height: u32,
    pub auto_hide: bool,
    pub widgets: Vec<String>,
}

impl Default for AweuiConfig {
    fn default() -> Self {
        Self {
            desktop: DesktopConfig {
                wallpaper: "/usr/share/backgrounds/aweos-default.png".to_string(),
                theme: "AWEUI-Dark".to_string(),
                icon_theme: "AWEUI-Icons".to_string(),
                font: "Sans 10".to_string(),
                font_size: 10,
                accent_color: "#3b82f6".to_string(),
            },
            input: InputConfig {
                repeat_rate: 25,
                repeat_delay: 200,
                tap_to_click: true,
                pointer_speed: 1.0,
            },
            wm: WmConfig {
                default_mode: "floating".to_string(),
                gap_size: 6,
                border_width: 2,
                active_border_color: "#3b82f6".to_string(),
                inactive_border_color: "#334155".to_string(),
                workspace_count: 4,
            },
            panel: PanelConfig {
                position: "top".to_string(),
                height: 32,
                auto_hide: false,
                widgets: vec![
                    "launcher".to_string(),
                    "workspaces".to_string(),
                    "window_title".to_string(),
                    "system_tray".to_string(),
                    "cpu_ram".to_string(),
                    "clock".to_string(),
                    "control_center_toggle".to_string(),
                ],
            },
        }
    }
}

impl AweuiConfig {
    pub fn load() -> Self {
        let mut path = dirs_config_dir().unwrap_or_else(|| PathBuf::from("/etc/aweui"));
        path.push("aweui");
        path.push("config.toml");

        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(cfg) = toml::from_str::<AweuiConfig>(&content) {
                    return cfg;
                }
            }
        }
        let sys_path = PathBuf::from("/etc/aweui/config.toml");
        if sys_path.exists() {
            if let Ok(content) = fs::read_to_string(&sys_path) {
                if let Ok(cfg) = toml::from_str::<AweuiConfig>(&content) {
                    return cfg;
                }
            }
        }

        let default_cfg = Self::default();
        let _ = default_cfg.save();
        default_cfg
    }

    pub fn save(&self) -> Result<(), String> {
        let mut path = dirs_config_dir().unwrap_or_else(|| PathBuf::from("/root/.config"));
        path.push("aweui");
        if let Err(e) = fs::create_dir_all(&path) {
            return Err(format!("Failed to create config dir: {}", e));
        }
        path.push("config.toml");
        let toml_str = toml::to_string_pretty(self).map_err(|e| e.to_string())?;
        fs::write(&path, toml_str).map_err(|e| e.to_string())
    }
}

fn dirs_config_dir() -> Option<PathBuf> {
    std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".config"))
}
