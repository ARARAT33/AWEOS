use std::env;
use std::io::{self, BufRead, Write};

pub fn factorial(n: u64) -> u64 {
    (1..=n).product()
}

pub fn evaluate_unary(op: &str, val: f64) -> Result<f64, String> {
    match op {
        "sqrt" => {
            if val < 0.0 {
                Err("Error: Square root of negative number".to_string())
            } else {
                Ok(val.sqrt())
            }
        }
        "sin" => Ok(val.to_radians().sin()),
        "cos" => Ok(val.to_radians().cos()),
        "tan" => Ok(val.to_radians().tan()),
        "log" | "log10" => {
            if val <= 0.0 {
                Err("Error: Logarithm of non-positive number".to_string())
            } else {
                Ok(val.log10())
            }
        }
        "ln" => {
            if val <= 0.0 {
                Err("Error: Natural log of non-positive number".to_string())
            } else {
                Ok(val.ln())
            }
        }
        "fact" => {
            if val < 0.0 || val.fract() != 0.0 || val > 20.0 {
                Err("Error: Factorial requires integer 0 <= n <= 20".to_string())
            } else {
                Ok(factorial(val as u64) as f64)
            }
        }
        "abs" => Ok(val.abs()),
        _ => Err(format!("Unknown unary operation: {}", op)),
    }
}

pub fn evaluate_binary(op: &str, a: f64, b: f64) -> Result<f64, String> {
    match op {
        "add" | "+" => Ok(a + b),
        "sub" | "-" => Ok(a - b),
        "mul" | "*" => Ok(a * b),
        "div" | "/" => {
            if b == 0.0 {
                Err("Error: Division by zero".to_string())
            } else {
                Ok(a / b)
            }
        }
        "pow" | "^" => Ok(a.powf(b)),
        "mod" | "%" => {
            if b == 0.0 {
                Err("Error: Modulo by zero".to_string())
            } else {
                Ok(a % b)
            }
        }
        _ => Err(format!("Unknown binary operation: {}", op)),
    }
}

pub fn run_interactive() {
    println!("AWEUI Scientific Calculator - Interactive Mode");
    println!("Commands:");
    println!("  <op> <num1> <num2>    (e.g., + 12 30, pow 2 10, mod 15 4)");
    println!("  <op> <num>           (e.g., sqrt 16, sin 90, log 100, fact 5)");
    println!("  quit / exit          (Exit calculator)");

    let stdin = io::stdin();
    let mut handle = stdin.lock();

    loop {
        print!("calc> ");
        if io::stdout().flush().is_err() {
            break;
        }

        let mut line = String::new();
        if handle.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }

        let tokens: Vec<&str> = line.trim().split_whitespace().collect();
        if tokens.is_empty() {
            continue;
        }

        match tokens[0] {
            "quit" | "exit" => break,
            op => {
                if tokens.len() == 2 {
                    if let Ok(val) = tokens[1].parse::<f64>() {
                        match evaluate_unary(op, val) {
                            Ok(res) => println!("= {}", res),
                            Err(e) => println!("{}", e),
                        }
                    } else {
                        println!("Invalid number argument: {}", tokens[1]);
                    }
                } else if tokens.len() == 3 {
                    let a = tokens[1].parse::<f64>();
                    let b = tokens[2].parse::<f64>();
                    match (a, b) {
                        (Ok(num1), Ok(num2)) => match evaluate_binary(op, num1, num2) {
                            Ok(res) => println!("= {}", res),
                            Err(e) => println!("{}", e),
                        },
                        _ => println!("Invalid numerical arguments"),
                    }
                } else {
                    println!("Usage: <op> <num1> [num2]");
                }
            }
        }
    }
}

fn main() {
    aweui_framework::init();
    println!("========================================");
    println!("      AWEUI Scientific Calculator       ");
    println!("========================================");

    let args: Vec<String> = env::args().collect();

    if args.len() == 2 && args[1] == "-i" {
        run_interactive();
    } else if args.len() == 3 {
        let op = &args[1];
        if let Ok(val) = args[2].parse::<f64>() {
            match evaluate_unary(op, val) {
                Ok(res) => println!("Result: {} {} = {}", op, val, res),
                Err(e) => println!("{}", e),
            }
        } else {
            println!("Invalid number: {}", args[2]);
        }
    } else if args.len() == 4 {
        let op = &args[1];
        let a: f64 = args[2].parse().unwrap_or(0.0);
        let b: f64 = args[3].parse().unwrap_or(0.0);

        match evaluate_binary(op, a, b) {
            Ok(res) => println!("Result: {} {} {} = {}", a, op, b, res),
            Err(e) => println!("{}", e),
        }
    } else {
        println!("Usage:");
        println!("  aweui-calculator -i                            (Interactive mode)");
        println!("  aweui-calculator <unary_op> <num>               (e.g., sqrt 16, sin 90)");
        println!("  aweui-calculator <binary_op> <num1> <num2>       (e.g., add 12 30, pow 2 10)");
        println!("Operations: +, -, *, /, pow, mod, sqrt, sin, cos, tan, log, ln, fact, abs");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_evaluate_binary_operations() {
        assert_eq!(evaluate_binary("+", 10.0, 5.0).unwrap(), 15.0);
        assert_eq!(evaluate_binary("sub", 10.0, 3.0).unwrap(), 7.0);
        assert_eq!(evaluate_binary("mul", 4.0, 3.0).unwrap(), 12.0);
        assert_eq!(evaluate_binary("div", 20.0, 4.0).unwrap(), 5.0);
        assert!(evaluate_binary("div", 10.0, 0.0).is_err());
        assert_eq!(evaluate_binary("pow", 2.0, 3.0).unwrap(), 8.0);
        assert_eq!(evaluate_binary("mod", 10.0, 3.0).unwrap(), 1.0);
    }

    #[test]
    fn test_evaluate_unary_operations() {
        assert_eq!(evaluate_unary("sqrt", 16.0).unwrap(), 4.0);
        assert!(evaluate_unary("sqrt", -4.0).is_err());
        assert!((evaluate_unary("sin", 90.0).unwrap() - 1.0).abs() < 1e-5);
        assert!((evaluate_unary("cos", 0.0).unwrap() - 1.0).abs() < 1e-5);
        assert_eq!(evaluate_unary("log", 100.0).unwrap(), 2.0);
        assert_eq!(evaluate_unary("fact", 5.0).unwrap(), 120.0);
        assert_eq!(evaluate_unary("abs", -15.5).unwrap(), 15.5);
    }
}
