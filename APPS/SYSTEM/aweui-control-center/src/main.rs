use aweui_framework::ipc::{send_request, IpcRequest, IpcResponse};

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("         AWEUI Control Center           ");
    println!("========================================");

    let socket = "/tmp/aweui-ipc.sock";
    println!("[Control Center] System Quick Service Status:");

    // Check network interface
    if std::path::Path::new("/sys/class/net/eth0").exists() || std::path::Path::new("/sys/class/net/wlan0").exists() {
        println!(" [Network] Primary network interface detected.");
    } else {
        println!(" [Network] Querying network service...");
    }

    match send_request(socket, IpcRequest::ToggleControlCenter) {
        Ok(IpcResponse::Success(msg)) => println!(" IPC Status: {}", msg),
        _ => println!(" IPC Status: Offline mode (compositor socket inactive)"),
    }
}
