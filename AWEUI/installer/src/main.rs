pub mod config;
pub mod disk;
pub mod engine;
pub mod i18n;
pub mod partition;
pub mod state;
pub mod ui;

use i18n::I18n;
use state::{InstallerState, InstallerStep};
use std::io::{self, BufRead};

fn main() {
    println!("Initializing AWEOS Native Wayland Graphical Installer...");

    let mut state = InstallerState::default();
    let mut i18n = I18n::new(state.language);

    let disks = disk::discover_disks();
    if !disks.is_empty() {
        state.selected_disk = Some(disks[0].clone());
    }

    let stdin = io::stdin();
    let mut handle = stdin.lock();

    loop {
        println!("{}", ui::render_screen(&state, &i18n));

        if state.current_step == InstallerStep::Complete || matches!(state.current_step, InstallerStep::Error(_)) {
            break;
        }

        if state.current_step == InstallerStep::Installing {
            let target_mount = std::path::Path::new("/mnt/aweos-target");
            let res = engine::execute_installation(&mut state, target_mount, |st, pct, op| {
                st.progress_percent = pct;
                st.current_operation = op.to_string();
                println!("[INSTALL ENGINE {}%] {}", pct, op);
            });

            match res {
                Ok(_) => {
                    state.current_step = InstallerStep::Complete;
                }
                Err(e) => {
                    state.current_step = InstallerStep::Error(e);
                }
            }
            continue;
        }

        print!("Select Option ([C]ontinue, [B]ack, [1-3] Lang, [I]nstall, [Q]uit): ");
        let mut line = String::new();
        if handle.read_line(&mut line).unwrap_or(0) == 0 {
            // Non-interactive stdin or piped execution: advance state automatically
            state.next_step();
            i18n.set_language(state.language);
            continue;
        }

        let input = line.trim().to_uppercase();
        match input.as_str() {
            "Q" => {
                println!("Exiting AWEOS Installer.");
                break;
            }
            "1" => {
                state.language = i18n::Language::English;
                i18n.set_language(state.language);
            }
            "2" => {
                state.language = i18n::Language::Armenian;
                i18n.set_language(state.language);
            }
            "3" => {
                state.language = i18n::Language::Russian;
                i18n.set_language(state.language);
            }
            "B" => {
                state.prev_step();
            }
            "I" if state.current_step == InstallerStep::Summary => {
                state.current_step = InstallerStep::Installing;
            }
            _ => {
                state.next_step();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_installer_workflow_navigation() {
        let mut state = InstallerState::default();
        assert_eq!(state.current_step, InstallerStep::Welcome);

        state.next_step();
        assert_eq!(state.current_step, InstallerStep::Language);

        state.next_step();
        assert_eq!(state.current_step, InstallerStep::Keyboard);

        state.prev_step();
        assert_eq!(state.current_step, InstallerStep::Language);
    }

    #[test]
    fn test_i18n_translations() {
        let mut i18n = I18n::new(i18n::Language::English);
        assert_eq!(i18n.t("welcome_title"), "Welcome to AWEOS");

        i18n.set_language(i18n::Language::Armenian);
        assert_eq!(i18n.t("welcome_title"), "Բարի գալուստ AWEOS");

        i18n.set_language(i18n::Language::Russian);
        assert_eq!(i18n.t("welcome_title"), "Добро пожаловать в AWEOS");
    }

    #[test]
    fn test_ui_rendering() {
        let state = InstallerState::default();
        let i18n = I18n::new(state.language);
        let rendered = ui::render_screen(&state, &i18n);
        assert!(rendered.contains("AWEOS INSTALLER UI"));
        assert!(rendered.contains("WELCOME TO AWEOS"));
    }

    #[test]
    fn test_installation_engine_execution() {
        let mut state = InstallerState::default();
        let disks = disk::discover_disks();
        state.selected_disk = Some(disks[0].clone());

        let test_target = std::path::Path::new("build/test-target");
        let res = engine::execute_installation(&mut state, test_target, |st, pct, op| {
            st.progress_percent = pct;
            st.current_operation = op.to_string();
        });

        if let Err(ref e) = res {
            println!("Engine Execution Error in test: {}", e);
        }

        assert!(res.is_ok());
        assert!(test_target.join("etc/hostname").exists());
        assert!(test_target.join("etc/passwd").exists());
        assert!(test_target.join("etc/shadow").exists());
        assert!(test_target.join("boot/limine.conf").exists());

        // Cleanup
        let _ = std::fs::remove_dir_all(test_target);
    }
}
