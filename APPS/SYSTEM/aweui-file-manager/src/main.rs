use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("           AWEUI File Manager           ");
    println!("========================================");

    let target_dir = env::args().nth(1).unwrap_or_else(|| "/home/aweos".to_string());
    let path = PathBuf::from(&target_dir);

    println!("Browsing Directory: {}", path.display());
    if path.exists() {
        if let Ok(entries) = fs::read_dir(&path) {
            for entry in entries.flatten() {
                let metadata = entry.metadata();
                let is_dir = metadata.as_ref().map(|m| m.is_dir()).unwrap_or(false);
                let size = metadata.as_ref().map(|m| m.len()).unwrap_or(0);
                let file_name = entry.file_name();
                let name = file_name.to_string_lossy();
                let prefix = if is_dir { "[DIR] " } else { "[FILE]" };
                println!(" {:<6} {:<30} ({} bytes)", prefix, name, size);
            }
        }
    } else {
        println!("Error: Directory {} does not exist.", path.display());
    }
}
