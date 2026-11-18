use std::fs;
use aweui_framework::ipc::{default_socket_path, socket_is_active};

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("          AWEUI Diagnostics             ");
    println!("========================================");

    println!("Checking system integration & Wayland compositor status...");
    let socket_path = default_socket_path();
    if socket_is_active() {
        println!(" [OK] AWEUI Compositor IPC listener is active ({socket_path}).");
    } else {
        println!(" [WARN] AWEUI Compositor IPC listener is offline ({socket_path}).");
    }

    if let Ok(release) = fs::read_to_string("/etc/os-release") {
        println!("\nOS Environment:\n{}", release);
    }
}
