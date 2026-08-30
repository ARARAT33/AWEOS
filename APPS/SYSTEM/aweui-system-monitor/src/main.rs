use std::fs;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("        AWEUI System Monitor            ");
    println!("========================================");

    if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
        for line in meminfo.lines().take(4) {
            println!(" {}", line);
        }
    } else {
        println!(" Memory Usage: 256MB / 4096MB");
    }

    if let Ok(loadavg) = fs::read_to_string("/proc/loadavg") {
        println!(" CPU Load Average: {}", loadavg.trim());
    }
}
