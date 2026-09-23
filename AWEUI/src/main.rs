mod config;
mod desktop;
mod theme;
mod input;
mod ipc;
mod launcher;
mod notifications;
mod outputs;
mod renderer;
mod session;
mod shell;
mod state;
mod wm;
mod wayland;
mod workspaces;

use state::AweuiState;
use std::sync::{Arc, Mutex};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    println!("AWEOS AYUI — native Wayland desktop session");
    println!("AYUI is the primary desktop; GNOME remains a secondary session.");

    let state = Arc::new(Mutex::new(AweuiState::new()));
    {
        let guard = state.lock().unwrap();
        guard.ipc_server.lock().unwrap().start_listener(Arc::clone(&state));
    }
    {
        let mut guard = state.lock().unwrap();
        let workspace_count = guard.workspaces.workspaces.len();
        let app_count = guard.session.launcher.apps.len();
        guard.session.start(workspace_count, app_count);
    }

    println!("AWEOS BOOT SUCCESS: mode=ayui");
    println!("AYUI services online: Wayland/XDG shell, renderer, input/seat, launcher, WM, workspaces, notifications, control center");

    wayland::run(state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compositor_state_creation() {
        let state = AweuiState::new();
        assert_eq!(state.workspaces.workspaces.len(), 4);
        assert!(state.running);
        assert_eq!(state.session.desktop_name, "AYUI");
    }
}
