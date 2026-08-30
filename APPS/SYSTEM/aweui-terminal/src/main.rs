use nix::unistd::execvp;
use std::ffi::CString;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("            AWEUI Terminal              ");
    println!("========================================");
    println!("Launching Unix PTY shell session (/bin/sh)...");

    let shell = CString::new("/bin/sh").unwrap();
    let args = [shell.clone()];
    let _ = execvp(&shell, &args);
}
