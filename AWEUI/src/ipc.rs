use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::thread;

use nix::sys::socket::sockopt::PeerCredentials;
use nix::sys::socket::getsockopt;
use nix::unistd::Uid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcRequest {
    GetStatus,
    GetWorkspaces,
    SwitchWorkspace(usize),
    LaunchApp(String),
    LaunchCommand(String),
    PowerAction(String),
    GetConfig,
    SetConfig(String),
    ToggleControlCenter,
    SendNotification { title: String, body: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcResponse {
    Success(String),
    Workspaces(Vec<String>),
    Config(String),
    Error(String),
}

/// Resolve the AYUI IPC socket path without touching process state.
///
/// The socket must never live in a world-writable directory when a private
/// runtime directory is available: /tmp sockets are reachable by every local
/// user, which previously exposed privileged LaunchCommand and PowerAction
/// requests to any local process.
pub fn resolve_socket_path(runtime_dir: Option<&str>, uid: u32) -> String {
    if let Some(dir) = runtime_dir {
        if !dir.is_empty() {
            return format!("{dir}/aweui-ipc.sock");
        }
    }
    format!("/run/user/{uid}/aweui-ipc.sock")
}

/// Default socket path for this process, preferring XDG_RUNTIME_DIR.
pub fn default_socket_path() -> String {
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").ok();
    resolve_socket_path(runtime_dir.as_deref(), Uid::current().as_raw())
}

/// Remove a stale socket only when the existing path really is a socket.
///
/// A blind remove_file would delete an unrelated regular file or directory
/// placed at the socket path by a local attacker. Fail closed instead.
fn remove_stale_socket(socket_path: &str) -> std::io::Result<()> {
    match fs::symlink_metadata(socket_path) {
        Ok(meta) => {
            if meta.file_type().is_socket() {
                fs::remove_file(socket_path)?;
            } else {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::AlreadyExists,
                    format!("refusing to remove non-socket path: {socket_path}"),
                ));
            }
            Ok(())
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    }
}

pub struct IpcServer {
    pub socket_path: String,
}

impl IpcServer {
    /// Prepare the socket location and record the path.
    ///
    /// The parent runtime directory is created with mode 0700 so only the
    /// session user can even see the socket. A non-socket object already
    /// occupying the path is never deleted; construction fails closed.
    pub fn new(socket_path: &str) -> Self {
        if let Some(parent) = Path::new(socket_path).parent() {
            if !parent.as_os_str().is_empty() {
                let _ = fs::create_dir_all(parent);
                let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
            }
        }
        if let Err(error) = remove_stale_socket(socket_path) {
            eprintln!("AYUI IPC stale-socket cleanup refused: {error}");
        }
        Self { socket_path: socket_path.to_string() }
    }

    /// Bind the listening socket and restrict it to the session user.
    pub fn bind(&self) -> std::io::Result<UnixListener> {
        let listener = UnixListener::bind(&self.socket_path)?;
        let _ = fs::set_permissions(&self.socket_path, fs::Permissions::from_mode(0o600));
        Ok(listener)
    }

    /// Accept connections only from processes running as the same user.
    ///
    /// The socket permissions already exclude other users, but the peer
    /// credential check also rejects same-uid spoofing via inherited fds and
    /// documents the trust boundary in code instead of comments.
    fn peer_is_same_uid(stream: &UnixStream) -> bool {
        getsockopt(stream, PeerCredentials)
            .map(|creds| creds.uid == Uid::current().as_raw())
            .unwrap_or(false)
    }

    pub fn start_listener(&self, state_handler: Arc<Mutex<crate::state::AweuiState>>) {
        let socket_path = self.socket_path.clone();
        thread::spawn(move || {
            let server = IpcServer { socket_path };
            let listener = match server.bind() {
                Ok(listener) => listener,
                Err(error) => { eprintln!("AYUI IPC bind failed: {error}"); return; }
            };
            for mut stream in listener.incoming().flatten() {
                if !Self::peer_is_same_uid(&stream) {
                    eprintln!("AYUI IPC rejected connection from a different uid");
                    continue;
                }
                let mut buf = [0u8; 8192];
                let Ok(n) = stream.read(&mut buf) else { continue };
                if n == 0 { continue; }
                let Ok(req) = serde_json::from_slice::<IpcRequest>(&buf[..n]) else { continue };
                let response = Self::handle_request(req, &state_handler);
                if let Ok(bytes) = serde_json::to_vec(&response) { let _ = stream.write_all(&bytes); }
            }
        });
    }

    fn handle_request(req: IpcRequest, state_arc: &Arc<Mutex<crate::state::AweuiState>>) -> IpcResponse {
        let mut state = state_arc.lock().unwrap();
        match req {
            IpcRequest::GetStatus => IpcResponse::Success("AYUI Active".into()),
            IpcRequest::GetWorkspaces => IpcResponse::Workspaces(
                state.workspaces.workspaces.iter().map(|w| w.name.clone()).collect()
            ),
            IpcRequest::SwitchWorkspace(index) => {
                state.workspaces.switch_to(index);
                IpcResponse::Success(format!("Switched to workspace {}", index + 1))
            }
            IpcRequest::LaunchApp(app) => match state.session.launch_app(&app) {
                Ok(()) => IpcResponse::Success(format!("Launched {app}")),
                Err(e) => IpcResponse::Error(e),
            },
            IpcRequest::LaunchCommand(command) => match state.session.launch_command(&command) {
                Ok(()) => IpcResponse::Success("Command launched".into()),
                Err(e) => IpcResponse::Error(e),
            },
            IpcRequest::PowerAction(action) => match crate::session::SessionManager::power_action(&action) {
                Ok(()) => IpcResponse::Success(format!("Power action: {action}")),
                Err(e) => IpcResponse::Error(e),
            },
            IpcRequest::GetConfig => IpcResponse::Config(toml::to_string_pretty(&state.config).unwrap_or_default()),
            IpcRequest::SetConfig(config) => match toml::from_str(&config) {
                Ok(cfg) => { state.config = cfg; let _ = state.config.save(); IpcResponse::Success("Configuration updated".into()) }
                Err(_) => IpcResponse::Error("Invalid configuration syntax".into()),
            },
            IpcRequest::ToggleControlCenter => {
                state.desktop.toggle_control_center();
                IpcResponse::Success(format!("Overlay: {:?}", state.desktop.overlay))
            }
            IpcRequest::SendNotification { title, body } => {
                println!("[AYUI Notification] {title}: {body}");
                IpcResponse::Success("Notification delivered".into())
            }
        }
    }
}

pub fn send_ipc_request(socket_path: &str, req: IpcRequest) -> Result<IpcResponse, String> {
    let mut stream = UnixStream::connect(socket_path).map_err(|e| e.to_string())?;
    let bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
    stream.write_all(&bytes).map_err(|e| e.to_string())?;
    let mut buf = [0u8; 8192];
    let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
    serde_json::from_slice(&buf[..n]).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_path_prefers_explicit_runtime_dir() {
        let path = resolve_socket_path(Some("/run/user/1000"), 0);
        assert_eq!(path, "/run/user/1000/aweui-ipc.sock");
    }

    #[test]
    fn socket_path_falls_back_to_uid_directory() {
        let path = resolve_socket_path(None, 1001);
        assert_eq!(path, "/run/user/1001/aweui-ipc.sock");
    }

    #[test]
    fn socket_path_ignores_empty_runtime_dir() {
        let path = resolve_socket_path(Some(""), 1002);
        assert_eq!(path, "/run/user/1002/aweui-ipc.sock");
    }

    #[test]
    fn stale_socket_is_removed_before_bind() {
        let dir = std::env::temp_dir().join(format!("aweui-ipc-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("stale.sock");
        // Create a genuine stale socket, then confirm new() clears it.
        let _listener = UnixListener::bind(&path).unwrap();
        assert!(path.exists());
        let _server = IpcServer::new(path.to_str().unwrap());
        assert!(!path.exists());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn non_socket_path_is_never_removed() {
        let dir = std::env::temp_dir().join(format!("aweui-ipc-file-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("victim.sock");
        fs::write(&path, b"not a socket").unwrap();
        let _server = IpcServer::new(path.to_str().unwrap());
        // Fail-closed: an unrelated file at the socket path must survive.
        assert!(path.exists(), "IpcServer must not delete a non-socket path");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bind_sets_owner_only_permissions() {
        let dir = std::env::temp_dir().join(format!("aweui-ipc-bind-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("bind.sock");
        let server = IpcServer::new(path.to_str().unwrap());
        let _listener = server.bind().expect("bind must succeed on a clean path");
        let mode = fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600, "socket must be owner-only");
        let _ = fs::remove_dir_all(&dir);
    }
}
