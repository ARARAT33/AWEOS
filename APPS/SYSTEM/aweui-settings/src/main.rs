use aweui_framework::ipc::{send_request, IpcRequest, IpcResponse};
use std::env;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("        AWEUI Settings Manager          ");
    println!("========================================");

    let socket = "/tmp/aweui-ipc.sock";
    let args: Vec<String> = env::args().collect();

    if args.len() > 1 && args[1] == "--get-config" {
        match send_request(socket, IpcRequest::GetConfig) {
            Ok(IpcResponse::Config(cfg)) => println!("Current AWEUI Configuration:\n{}", cfg),
            Ok(other) => println!("Response: {:?}", other),
            Err(e) => println!("Error getting config: {}", e),
        }
    } else {
        println!("Available Settings Modules:");
        println!(" 1. Appearance & Theme");
        println!(" 2. Display & Resolution");
        println!(" 3. Window Management & Workspaces");
        println!(" 4. Keyboard & Input");
        println!(" 5. Network & Audio");
        println!(" 6. System Information");
        println!("\nUse --get-config to query active compositor configuration.");
    }
}
