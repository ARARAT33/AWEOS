pub mod widgets {
    pub struct ClockWidget;
    impl ClockWidget {
        pub fn now_string() -> String {
            use std::time::SystemTime;
            if let Ok(duration) = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH) {
                let secs = duration.as_secs();
                let hours = (secs / 3600) % 24;
                let mins = (secs / 60) % 60;
                let secs = secs % 60;
                format!("{:02}:{:02}:{:02} UTC", hours, mins, secs)
            } else {
                "00:00:00 UTC".to_string()
            }
        }
    }

    pub struct CpuRamWidget;
    impl CpuRamWidget {
        pub fn get_info() -> (u32, u32) {
            (15, 42)
        }
    }
}

pub struct Panel {
    pub height: u32,
    pub position: String,
}

impl Panel {
    pub fn new(height: u32, position: &str) -> Self {
        Self {
            height,
            position: position.to_string(),
        }
    }
}
