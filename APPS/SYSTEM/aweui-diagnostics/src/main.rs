use aweui_framework::ipc::default_socket_path;
use std::fs;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("          AWEUI Diagnostics             ");
    println!("========================================");

    println!("Checking system integration & Wayland compositor status...");
    let socket = default_socket_path();
    if std::path::Path::new(&socket).exists() {
        println!(" [OK] AWEUI Compositor IPC Socket ({socket}) is active.");
    } else {
        println!(" [WARN] AWEUI Compositor IPC Socket is offline.");
    }

    if let Ok(release) = fs::read_to_string("/etc/os-release") {
        println!("\nOS Environment:\n{}", release);
    }
}
