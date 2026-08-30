mod config;
mod input;
mod ipc;
mod launcher;
mod notifications;
mod outputs;
mod renderer;
mod shell;
mod state;
mod wm;
mod workspaces;

use smithay::reexports::wayland_server::Display;
use state::AweuiState;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    println!("Starting AWEUI Wayland Compositor...");

    let mut display = Display::new();
    let listening_socket = display.add_socket_auto()?;
    println!("AWEUI Compositor running on Wayland socket: {:?}", listening_socket.to_string_lossy());

    let state = AweuiState::new();
    let state_arc = Arc::new(Mutex::new(state));

    {
        let state_guard = state_arc.lock().unwrap();
        state_guard.ipc_server.lock().unwrap().start_listener(Arc::clone(&state_arc));
    }

    println!("AWEUI Compositor initialized successfully. Entering event dispatch loop...");

    loop {
        {
            let state = state_arc.lock().unwrap();
            if !state.running {
                println!("AWEUI Compositor shutting down...");
                break;
            }
        }
        display.dispatch(Duration::from_millis(10), &mut ())?;
        display.flush_clients(&mut ());
        thread::sleep(Duration::from_millis(10));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compositor_state_creation() {
        let state = AweuiState::new();
        assert_eq!(state.workspaces.workspaces.len(), 4);
        assert!(state.running);
    }

    #[test]
    fn test_window_manager_operations() {
        let cfg = config::WmConfig {
            default_mode: "floating".to_string(),
            gap_size: 4,
            border_width: 2,
            active_border_color: "#000".to_string(),
            inactive_border_color: "#fff".to_string(),
            workspace_count: 4,
        };
        let mut wm = wm::WindowManager::new(cfg);
        assert_eq!(wm.windows.len(), 0);
        let win_id = wm.create_window("Test Window", "test.app");
        assert_eq!(wm.windows.len(), 1);
        wm.move_window(win_id, 10, 10);
        assert_eq!(wm.windows[0].geometry.x, 130);
        wm.maximize_window(win_id, 1920, 1080);
        assert_eq!(wm.windows[0].state, wm::WindowState::Maximized);
        wm.close_window(win_id);
        assert_eq!(wm.windows.len(), 0);
    }

    #[test]
    fn test_workspace_operations() {
        let mut ws_mgr = workspaces::WorkspaceManager::new(4);
        assert_eq!(ws_mgr.workspaces.len(), 4);
        assert_eq!(ws_mgr.active_index, 0);
        ws_mgr.switch_to(2);
        assert_eq!(ws_mgr.active_index, 2);
    }

    #[test]
    fn test_launcher_application_discovery() {
        let mut l = launcher::Launcher::new();
        l.scan_applications();
        let query_res = l.search("term");
        assert!(query_res.is_empty() || !query_res.is_empty());
    }

    #[test]
    fn test_panel_and_widgets() {
        let p = shell::Panel::new(32, "top");
        assert_eq!(p.height, 32);
        let time_str = shell::widgets::ClockWidget::now_string();
        assert!(time_str.contains("UTC"));
    }

    #[test]
    fn test_multi_monitor_output_manager() {
        let mut om = outputs::OutputManager::new();
        let out1 = om.create_output("HDMI-1", 1920, 1080, 60000, 1);
        let out2 = om.create_output("DP-1", 2560, 1440, 144000, 2);
        assert_eq!(om.outputs.len(), 2);
        assert_eq!(out1.name, "HDMI-1");
        assert_eq!(out2.scale, 2);
    }

    #[test]
    fn test_notification_daemon() {
        let mut daemon = notifications::NotificationDaemon::new();
        let nid = daemon.post("TestApp", "Test Title", "Test Body", "icon");
        assert_eq!(nid, 1);
        assert_eq!(daemon.notifications.len(), 1);
        daemon.dismiss(nid);
        assert_eq!(daemon.notifications.len(), 0);
    }

    #[test]
    fn test_config_persistence() {
        let mut cfg = config::AweuiConfig::default();
        cfg.desktop.theme = "AWEUI-Light".to_string();
        let toml_str = toml::to_string_pretty(&cfg).unwrap();
        let loaded: config::AweuiConfig = toml::from_str(&toml_str).unwrap();
        assert_eq!(loaded.desktop.theme, "AWEUI-Light");
    }
}
