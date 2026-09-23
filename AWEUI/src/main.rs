mod config;
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
mod workspaces;

use smithay::reexports::wayland_server::Display;
use state::AweuiState;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();
    println!("AWEOS AYUI — native desktop session");
    println!("AYUI is the primary AWEOS desktop; GNOME remains a secondary session.");

    let mut display = Display::new();
    let listening_socket = display.add_socket_auto()?;
    println!("AWEUI Wayland socket: {:?}", listening_socket.to_string_lossy());

    let state = AweuiState::new();
    let state_arc = Arc::new(Mutex::new(state));

    {
        let state_guard = state_arc.lock().unwrap();
        state_guard.ipc_server.lock().unwrap().start_listener(Arc::clone(&state_arc));
    }

    {
        let mut state = state_arc.lock().unwrap();
        let workspace_count = state.workspaces.workspaces.len();
        let app_count = state.session.launcher.apps.len();
        state.session.start(workspace_count, app_count);
    }

    println!("AWEOS BOOT SUCCESS: mode=ayui");
    println!("AYUI services online: launcher, WM, workspaces, notifications, control center, session manager");

    loop {
        if !state_arc.lock().unwrap().running {
            println!("AWEUI shutting down...");
            break;
        }
        display.dispatch(Duration::from_millis(10), &mut ())?;
        display.flush_clients(&mut ());
        state_arc.lock().unwrap().session.reap_finished();
        thread::sleep(Duration::from_millis(2));
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
        assert_eq!(state.session.desktop_name, "AYUI");
    }
}
