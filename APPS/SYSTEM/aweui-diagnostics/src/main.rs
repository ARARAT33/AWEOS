use std::fs;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("          AWEUI Diagnostics             ");
    println!("========================================");

    println!("Checking system integration & Wayland compositor status...");
    if std::path::Path::new("/tmp/aweui-ipc.sock").exists() {
        println!(" [OK] AWEUI Compositor IPC Socket (/tmp/aweui-ipc.sock) is active.");
    } else {
        println!(" [WARN] AWEUI Compositor IPC Socket is offline.");
    }

    if let Ok(release) = fs::read_to_string("/etc/os-release") {
        println!("\nOS Environment:\n{}", release);
    }
}
