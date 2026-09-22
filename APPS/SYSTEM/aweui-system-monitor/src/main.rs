use std::fs;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("        AWEUI System Monitor            ");
    println!("========================================");

    match fs::read_to_string("/proc/meminfo") {
        Ok(meminfo) => {
            for line in meminfo.lines().take(4) {
                println!(" {}", line);
            }
        }
        Err(e) => {
            println!(" Memory metrics unavailable: {}", e);
        }
    }

    match fs::read_to_string("/proc/loadavg") {
        Ok(loadavg) => println!(" CPU Load Average: {}", loadavg.trim()),
        Err(e) => println!(" CPU load unavailable: {}", e),
    }
}
