use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Notification {
    pub id: u64,
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub icon: String,
    pub timestamp: u64,
}

pub struct NotificationDaemon {
    pub notifications: VecDeque<Notification>,
    pub next_id: u64,
    pub dnd_mode: bool,
}

impl NotificationDaemon {
    pub fn new() -> Self {
        Self {
            notifications: VecDeque::new(),
            next_id: 1,
            dnd_mode: false,
        }
    }

    pub fn post(&mut self, app_name: &str, title: &str, body: &str, icon: &str) -> u64 {
        let id = self.next_id;
        self.next_id += 1;

        if !self.dnd_mode {
            let notif = Notification {
                id,
                app_name: app_name.to_string(),
                title: title.to_string(),
                body: body.to_string(),
                icon: icon.to_string(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
            };
            self.notifications.push_front(notif);
            if self.notifications.len() > 50 {
                self.notifications.pop_back();
            }
        }
        id
    }

    pub fn dismiss(&mut self, id: u64) {
        self.notifications.retain(|n| n.id != id);
    }

    pub fn clear(&mut self) {
        self.notifications.clear();
    }
}
