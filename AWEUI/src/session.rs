use crate::launcher::Launcher;
use std::process::{Child, Command, Stdio};

pub struct SessionManager {
    pub desktop_name: String,
    pub launcher: Launcher,
    pub started: bool,
    children: Vec<Child>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self { desktop_name: "AYUI".into(), launcher: Launcher::new(), started: false, children: Vec::new() }
    }

    pub fn start(&mut self, workspace_count: usize, app_count: usize) {
        self.started = true;
        println!("AYUI session ready: {workspace_count} workspaces, {app_count} applications");
    }

    pub fn launch_command(&mut self, command: &str) -> Result<(), String> {
        let tokens = shell_words(command)?;
        let (program, args) = tokens.split_first().ok_or_else(|| "empty command".to_string())?;
        let child = Command::new(program).args(args)
            .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
            .spawn().map_err(|e| format!("failed to launch {program}: {e}"))?;
        self.children.push(child);
        Ok(())
    }

    pub fn launch_app(&mut self, app_name: &str) -> Result<(), String> {
        let app = self.launcher.apps.iter()
            .find(|a| a.name.eq_ignore_ascii_case(app_name) || a.exec == app_name)
            .cloned().ok_or_else(|| format!("application not found: {app_name}"))?;
        self.launch_command(&app.exec)
    }

    pub fn reap_finished(&mut self) {
        self.children.retain_mut(|child| match child.try_wait() {
            Ok(Some(_)) | Err(_) => false,
            Ok(None) => true,
        });
    }

    pub fn power_action(action: &str) -> Result<(), String> {
        match action {
            "shutdown" => Command::new("poweroff").spawn(),
            "reboot" => Command::new("reboot").spawn(),
            "logout" => return Ok(()),
            _ => return Err("unsupported power action".into()),
        }.map(|_| ()).map_err(|e| e.to_string())
    }
}

fn shell_words(input: &str) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quote = None;
    let mut escape = false;
    for ch in input.chars() {
        if escape { cur.push(ch); escape = false; continue; }
        match ch {
            '\\' => escape = true,
            '\'' | '"' if quote == Some(ch) => quote = None,
            '\'' | '"' if quote.is_none() => quote = Some(ch),
            ' ' | '\t' if quote.is_none() => {
                if !cur.is_empty() { out.push(std::mem::take(&mut cur)); }
            }
            _ => cur.push(ch),
        }
    }
    if escape || quote.is_some() { return Err("unterminated quote or escape".into()); }
    if !cur.is_empty() { out.push(cur); }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::shell_words;
    #[test]
    fn parses_quoted_arguments() {
        assert_eq!(shell_words("app --title \"Hello World\"").unwrap(),
                   vec!["app", "--title", "Hello World"]);
    }
}
