use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppInfo {
    pub name: String,
    pub exec: String,
    pub icon: String,
    pub comment: String,
    pub categories: Vec<String>,
}

pub struct Launcher {
    pub apps: Vec<AppInfo>,
}

impl Launcher {
    pub fn new() -> Self {
        let mut launcher = Self { apps: Vec::new() };
        launcher.scan_applications();
        launcher
    }

    pub fn scan_applications(&mut self) {
        self.apps.clear();
        let dirs = vec![
            "/usr/share/applications",
            "/usr/local/share/applications",
            "/var/lib/awepkg",
        ];

        for dir in dirs {
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().and_then(|s| s.to_str()) == Some("desktop") {
                        if let Ok(content) = std::fs::read_to_string(&path) {
                            if let Some(app) = Self::parse_desktop_file(&content) {
                                self.apps.push(app);
                            }
                        }
                    } else if path.extension().and_then(|s| s.to_str()) == Some("meta") {
                        if let Ok(content) = std::fs::read_to_string(&path) {
                            if let Some(app) = Self::parse_aosin_meta(&content) {
                                self.apps.push(app);
                            }
                        }
                    }
                }
            }
        }
    }

    fn parse_desktop_file(content: &str) -> Option<AppInfo> {
        let mut name = None;
        let mut exec = None;
        let mut icon = None;
        let mut comment = None;
        let mut categories = Vec::new();

        for line in content.lines() {
            let line = line.trim();
            if line.starts_with("Name=") && name.is_none() {
                name = Some(line["Name=".len()..].to_string());
            } else if line.starts_with("Exec=") && exec.is_none() {
                exec = Some(line["Exec=".len()..].to_string());
            } else if line.starts_with("Icon=") && icon.is_none() {
                icon = Some(line["Icon=".len()..].to_string());
            } else if line.starts_with("Comment=") && comment.is_none() {
                comment = Some(line["Comment=".len()..].to_string());
            } else if line.starts_with("Categories=") {
                categories = line["Categories=".len()..]
                    .split(';')
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();
            }
        }

        if let (Some(name), Some(exec)) = (name, exec) {
            Some(AppInfo {
                name,
                exec,
                icon: icon.unwrap_or_else(|| "application-x-executable".to_string()),
                comment: comment.unwrap_or_default(),
                categories,
            })
        } else {
            None
        }
    }

    fn parse_aosin_meta(content: &str) -> Option<AppInfo> {
        let mut pkg_name = None;
        let mut pkg_desc = None;

        for line in content.lines() {
            let line = line.trim();
            if line.starts_with("PKG_NAME=") {
                pkg_name = Some(line["PKG_NAME=".len()..].to_string());
            } else if line.starts_with("PKG_DESC=") {
                pkg_desc = Some(line["PKG_DESC=".len()..].to_string());
            }
        }

        if let Some(name) = pkg_name {
            let exec = format!("/usr/bin/{}", name);
            Some(AppInfo {
                name: name.clone(),
                exec,
                icon: "package-x-generic".to_string(),
                comment: pkg_desc.unwrap_or_default(),
                categories: vec!["System".to_string()],
            })
        } else {
            None
        }
    }

    pub fn search(&self, query: &str) -> Vec<AppInfo> {
        let q = query.to_lowercase();
        self.apps
            .iter()
            .filter(|app| {
                app.name.to_lowercase().contains(&q)
                    || app.comment.to_lowercase().contains(&q)
                    || app.categories.iter().any(|c| c.to_lowercase().contains(&q))
            })
            .cloned()
            .collect()
    }
}
