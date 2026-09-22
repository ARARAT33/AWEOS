use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DiskInfo {
    pub device: String,
    pub name: String,
    pub model: String,
    pub size_bytes: u64,
    pub size_gb: f64,
    pub is_removable: bool,
    pub partitions: Vec<PartitionInfo>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PartitionInfo {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub size_gb: f64,
    pub fstype: String,
    pub mountpoint: Option<String>,
}

fn filesystem_type(device: &str) -> String {
    Command::new("blkid")
        .args(["-o", "value", "-s", "TYPE", device])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

fn mountpoint(device: &str) -> Option<String> {
    let mounts = std::fs::read_to_string("/proc/self/mountinfo").ok()?;
    for line in mounts.lines() {
        let mut fields = line.split_whitespace();
        let _mount_id = fields.next()?;
        let _parent_id = fields.next()?;
        let _major_minor = fields.next()?;
        let _root = fields.next()?;
        let mount_point = fields.next()?;
        let separator = fields.position(|field| field == "-")?;
        let _ = separator;
        // The device name is on the line after the '-' separator.
        let rest: Vec<&str> = line.split_whitespace().collect();
        if let Some(idx) = rest.iter().position(|f| *f == "-") {
            if rest.get(idx + 2).map(|s| *s == device).unwrap_or(false) {
                return Some(mount_point.replace("\\040", " "));
            }
        }
    }
    None
}

pub fn discover_disks() -> Vec<DiskInfo> {
    let mut disks = Vec::new();
    let sys_block = Path::new("/sys/block");

    let Ok(entries) = std::fs::read_dir(sys_block) else {
        return disks;
    };

    for entry in entries.flatten() {
        let dev_name = entry.file_name().to_string_lossy().to_string();
        if dev_name.starts_with("loop")
            || dev_name.starts_with("ram")
            || dev_name.starts_with("zram")
            || dev_name.starts_with("sr")
            || dev_name.starts_with("fd")
        {
            continue;
        }

        let device_path = format!("/dev/{}", dev_name);
        if !Path::new(&device_path).is_block_device() {
            continue;
        }

        let sys_path = entry.path();
        let sectors = std::fs::read_to_string(sys_path.join("size"))
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
            .unwrap_or(0);

        if sectors == 0 {
            continue;
        }

        let size_bytes = sectors.saturating_mul(512);
        let size_gb = size_bytes as f64 / (1024.0 * 1024.0 * 1024.0);
        let model = std::fs::read_to_string(sys_path.join("device/model"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Generic Storage Device".to_string());

        let is_removable = std::fs::read_to_string(sys_path.join("removable"))
            .map(|s| s.trim() == "1")
            .unwrap_or(false);

        let mut partitions = Vec::new();
        if let Ok(sub_entries) = std::fs::read_dir(&sys_path) {
            for sub_entry in sub_entries.flatten() {
                let sub_path = sub_entry.path();
                if !sub_path.join("partition").exists() {
                    continue;
                }

                let sub_name = sub_entry.file_name().to_string_lossy().to_string();
                let p_sectors = std::fs::read_to_string(sub_path.join("size"))
                    .ok()
                    .and_then(|s| s.trim().parse::<u64>().ok())
                    .unwrap_or(0);
                if p_sectors == 0 {
                    continue;
                }

                let path = format!("/dev/{}", sub_name);
                let p_bytes = p_sectors.saturating_mul(512);
                partitions.push(PartitionInfo {
                    name: sub_name,
                    path: path.clone(),
                    size_bytes: p_bytes,
                    size_gb: p_bytes as f64 / (1024.0 * 1024.0 * 1024.0),
                    fstype: filesystem_type(&path),
                    mountpoint: mountpoint(&path),
                });
            }
        }

        disks.push(DiskInfo {
            device: device_path,
            name: dev_name,
            model,
            size_bytes,
            size_gb,
            is_removable,
            partitions,
        });
    }

    disks.sort_by(|a, b| a.device.cmp(&b.device));
    disks
}
