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
        /// Return live CPU and RAM usage percentages on Linux.
        ///
        /// CPU usage is sampled over a short interval from /proc/stat. RAM usage
        /// is derived from MemTotal and MemAvailable in /proc/meminfo.
        /// When /proc is unavailable (for example during a unit test on a
        /// non-Linux host), the function falls back to zeros instead of using
        /// fabricated values.
        pub fn get_info() -> (u32, u32) {
            let cpu = Self::cpu_usage_percent().unwrap_or(0);
            let ram = Self::ram_usage_percent().unwrap_or(0);
            (cpu, ram)
        }

        fn cpu_usage_percent() -> Option<u32> {
            let first = Self::read_cpu_times()?;
            std::thread::sleep(std::time::Duration::from_millis(100));
            let second = Self::read_cpu_times()?;

            let idle_delta = second[3].saturating_sub(first[3]);
            let total_first: u64 = first.iter().sum();
            let total_second: u64 = second.iter().sum();
            let total_delta = total_second.saturating_sub(total_first);

            if total_delta == 0 {
                return Some(0);
            }

            let busy_delta = total_delta.saturating_sub(idle_delta);
            Some(((busy_delta * 100) / total_delta).min(100) as u32)
        }

        fn read_cpu_times() -> Option<[u64; 4]> {
            let content = std::fs::read_to_string("/proc/stat").ok()?;
            let line = content.lines().find(|line| line.starts_with("cpu "))?;
            let mut values = line.split_whitespace().skip(1).take(4);

            Some([
                values.next()?.parse().ok()?,
                values.next()?.parse().ok()?,
                values.next()?.parse().ok()?,
                values.next()?.parse().ok()?,
            ])
        }

        fn ram_usage_percent() -> Option<u32> {
            let content = std::fs::read_to_string("/proc/meminfo").ok()?;
            let mut total_kib = None;
            let mut available_kib = None;

            for line in content.lines() {
                let mut parts = line.split_whitespace();
                let key = parts.next()?;

                match key {
                    "MemTotal:" => total_kib = parts.next()?.parse::<u64>().ok(),
                    "MemAvailable:" => available_kib = parts.next()?.parse::<u64>().ok(),
                    _ => {}
                }
            }

            let total = total_kib?;
            let available = available_kib?;

            if total == 0 {
                return Some(0);
            }

            let used = total.saturating_sub(available);
            Some(((used * 100) / total).min(100) as u32)
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
