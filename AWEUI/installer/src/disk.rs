use std::fs;
use std::os::unix::fs::FileTypeExt;
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

fn is_block_device(path: &Path) -> bool {
    fs::metadata(path)
        .map(|m| m.file_type().is_block_device())
        .unwrap_or(false)
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
    let mounts = fs::read_to_string("/proc/self/mountinfo").ok()?;

    for line in mounts.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let separator = fields.iter().position(|field| *field == "-")?;

        if fields.get(separator + 2).copied() == Some(device) {
            return fields
                .get(4)
                .map(|mount| mount.replace("\\040", " "));
        }
    }

    None
}

pub fn discover_disks() -> Vec<DiskInfo> {
    let mut disks = Vec::new();
    let sys_block = Path::new("/sys/block");

    let Ok(entries) = fs::read_dir(sys_block) else {
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
        if !is_block_device(Path::new(&device_path)) {
            continue;
        }

        let sys_path = entry.path();
        let sectors = fs::read_to_string(sys_path.join("size"))
            .ok()
            .and_then(|s| s.trim().parse::<u64>().ok())
            .unwrap_or(0);

        if sectors == 0 {
            continue;
        }

        let size_bytes = sectors.saturating_mul(512);
        let size_gb = size_bytes as f64 / (1024.0 * 1024.0 * 1024.0);
        let model = fs::read_to_string(sys_path.join("device/model"))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Generic Storage Device".to_string());
        let is_removable = fs::read_to_string(sys_path.join("removable"))
            .map(|s| s.trim() == "1")
            .unwrap_or(false);

        let mut partitions = Vec::new();
        if let Ok(sub_entries) = fs::read_dir(&sys_path) {
            for sub_entry in sub_entries.flatten() {
                let sub_path = sub_entry.path();
                if !sub_path.join("partition").exists() {
                    continue;
                }

                let sub_name = sub_entry.file_name().to_string_lossy().to_string();
                let p_sectors = fs::read_to_string(sub_path.join("size"))
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
