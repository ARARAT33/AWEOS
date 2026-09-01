use std::path::Path;

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

pub fn discover_disks() -> Vec<DiskInfo> {
    let mut disks = Vec::new();
    let sys_block = Path::new("/sys/block");

    if !sys_block.exists() {
        disks.push(DiskInfo {
            device: "/dev/vda".to_string(),
            name: "vda".to_string(),
            model: "QEMU HARDDISK (Virtual)".to_string(),
            size_bytes: 34359738368,
            size_gb: 32.0,
            is_removable: false,
            partitions: vec![],
        });
        return disks;
    }

    if let Ok(entries) = std::fs::read_dir(sys_block) {
        for entry in entries.flatten() {
            let dev_name = entry.file_name().to_string_lossy().to_string();

            if dev_name.starts_with("loop") || dev_name.starts_with("ram") || dev_name.starts_with("zram") || dev_name.starts_with("sr") || dev_name.starts_with("fd") {
                continue;
            }

            let device_path = format!("/dev/{}", dev_name);
            let sys_path = entry.path();

            let size_file = sys_path.join("size");
            let sectors: u64 = if let Ok(content) = std::fs::read_to_string(&size_file) {
                content.trim().parse().unwrap_or(0)
            } else {
                0
            };

            if sectors == 0 {
                continue;
            }

            let size_bytes = sectors * 512;
            let size_gb = (size_bytes as f64) / (1024.0 * 1024.0 * 1024.0);

            let model_file = sys_path.join("device/model");
            let model = std::fs::read_to_string(&model_file)
                .unwrap_or_else(|_| "Generic Storage Device".to_string())
                .trim()
                .to_string();

            let rem_file = sys_path.join("removable");
            let is_removable = std::fs::read_to_string(&rem_file)
                .map(|s| s.trim() == "1")
                .unwrap_or(false);

            let mut partitions = Vec::new();
            if let Ok(sub_entries) = std::fs::read_dir(&sys_path) {
                for sub_entry in sub_entries.flatten() {
                    let sub_name = sub_entry.file_name().to_string_lossy().to_string();
                    if sub_name.starts_with(&dev_name) {
                        let part_size_file = sub_entry.path().join("size");
                        let p_sectors: u64 = std::fs::read_to_string(&part_size_file)
                            .map(|s| s.trim().parse().unwrap_or(0))
                            .unwrap_or(0);
                        let p_bytes = p_sectors * 512;
                        let p_gb = (p_bytes as f64) / (1024.0 * 1024.0 * 1024.0);

                        partitions.push(PartitionInfo {
                            name: sub_name.clone(),
                            path: format!("/dev/{}", sub_name),
                            size_bytes: p_bytes,
                            size_gb: p_gb,
                            fstype: "ext4".to_string(),
                            mountpoint: None,
                        });
                    }
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
    }

    if disks.is_empty() {
        disks.push(DiskInfo {
            device: "/dev/vda".to_string(),
            name: "vda".to_string(),
            model: "QEMU HARDDISK (Virtual Target)".to_string(),
            size_bytes: 34359738368,
            size_gb: 32.0,
            is_removable: false,
            partitions: vec![],
        });
    }

    disks
}
