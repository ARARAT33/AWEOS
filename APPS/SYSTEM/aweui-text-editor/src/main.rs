use std::env;
use std::fs;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("          AWEUI Text Editor             ");
    println!("========================================");

    if let Some(path) = env::args().nth(1) {
        println!("Opening file: {}", path);
        if let Ok(content) = fs::read_to_string(&path) {
            println!("--- File Contents ---\n{}\n--- End File ---", content);
        } else {
            println!("New file: {}", path);
        }
    } else {
        println!("Usage: aweui-text-editor <filename>");
    }
}
