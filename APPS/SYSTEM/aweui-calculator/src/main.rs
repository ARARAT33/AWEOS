use std::env;

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("           AWEUI Calculator             ");
    println!("========================================");

    let args: Vec<String> = env::args().collect();
    if args.len() == 4 {
        let op = &args[1];
        let a: f64 = args[2].parse().unwrap_or(0.0);
        let b: f64 = args[3].parse().unwrap_or(0.0);

        let result = match op.as_str() {
            "add" | "+" => a + b,
            "sub" | "-" => a - b,
            "mul" | "*" => a * b,
            "div" | "/" => {
                if b != 0.0 {
                    a / b
                } else {
                    println!("Error: Division by zero");
                    return;
                }
            }
            _ => {
                println!("Unknown operation: {}", op);
                return;
            }
        };
        println!("Result: {} {} {} = {}", a, op, b, result);
    } else {
        println!("Usage: aweui-calculator <add|sub|mul|div> <num1> <num2>");
        println!("Example: aweui-calculator add 12 30");
    }
}
