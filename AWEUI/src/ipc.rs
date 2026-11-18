use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::thread;

use nix::sys::socket::sockopt::PeerCredentials;
use nix::sys::socket::getsockopt;
use nix::unistd::Uid;

pub use aweui_framework::ipc::default_socket_path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcRequest {
    GetStatus,
    GetWorkspaces,
    SwitchWorkspace(usize),
    LaunchApp(String),
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

/// Validate a directory without following a symlink.
///
/// Runtime directories must belong to the effective user, be writable and
/// searchable by that user, and expose no permissions to group/other users.
fn validate_private_directory(path: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    let mode = metadata.permissions().mode();

    if !metadata.file_type().is_dir() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("IPC runtime path is not a real directory: {}", path.display()),
        ));
    }
    if metadata.uid() != Uid::effective().as_raw() {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("IPC runtime directory has the wrong owner: {}", path.display()),
        ));
    }
    if mode & 0o077 != 0 || mode & 0o700 != 0o700 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!(
                "IPC runtime directory must be owner-only (0700): {}",
                path.display()
            ),
        ));
    }

    Ok(())
}

/// Prepare only the dedicated socket directory. Never chmod an existing
/// XDG_RUNTIME_DIR, /run, /tmp, or another caller-supplied parent directory.
fn prepare_socket_parent(socket_path: &Path) -> io::Result<()> {
    let parent = socket_path.parent().filter(|path| !path.as_os_str().is_empty())
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "IPC socket path has no parent"))?;

    match fs::symlink_metadata(parent) {
        Ok(_) => validate_private_directory(parent),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            let runtime_dir = parent.parent().ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidInput, "IPC runtime directory has no parent")
            })?;
            validate_private_directory(runtime_dir)?;

            match fs::create_dir(parent) {
                Ok(()) => {
                    if let Err(error) = fs::set_permissions(parent, fs::Permissions::from_mode(0o700)) {
                        let _ = fs::remove_dir(parent);
                        return Err(error);
                    }
                    validate_private_directory(parent)
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                    validate_private_directory(parent)
                }
                Err(error) => Err(error),
            }
        }
        Err(error) => Err(error),
    }
}

/// Remove a stale socket, but never unlink a live listener or a non-socket
/// object. This avoids both destructive path cleanup and active-socket
/// replacement by a second AYUI process.
fn remove_stale_socket(socket_path: &str) -> io::Result<()> {
    match fs::symlink_metadata(socket_path) {
        Ok(metadata) if metadata.file_type().is_socket() => {
            match UnixStream::connect(socket_path) {
                Ok(_connection) => Err(io::Error::new(
                    io::ErrorKind::AddrInUse,
                    format!("AYUI IPC socket already has a live listener: {socket_path}"),
                )),
                Err(error)
                    if error.kind() == io::ErrorKind::ConnectionRefused
                        || error.kind() == io::ErrorKind::NotFound =>
                {
                    fs::remove_file(socket_path)
                }
                Err(error) => Err(error),
            }
        }
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            format!("refusing to replace a non-socket IPC path: {socket_path}"),
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

pub struct IpcServer {
    pub socket_path: String,
}

impl IpcServer {
    /// Record the socket path. Filesystem changes are deferred to bind(), where
    /// failures can be returned to the listener instead of being ignored.
    pub fn new(socket_path: &str) -> Self {
        Self {
            socket_path: socket_path.to_string(),
        }
    }

    /// Bind only inside an owner-controlled 0700 directory and expose the
    /// socket itself as 0600. All setup errors fail closed.
    pub fn bind(&self) -> io::Result<UnixListener> {
        let socket_path = Path::new(&self.socket_path);
        prepare_socket_parent(socket_path)?;
        remove_stale_socket(&self.socket_path)?;

        let listener = UnixListener::bind(&self.socket_path)?;
        if let Err(error) =
            fs::set_permissions(&self.socket_path, fs::Permissions::from_mode(0o600))
        {
            drop(listener);
            let _ = fs::remove_file(&self.socket_path);
            return Err(error);
        }

        let metadata = match fs::symlink_metadata(&self.socket_path) {
            Ok(metadata) => metadata,
            Err(error) => {
                drop(listener);
                let _ = fs::remove_file(&self.socket_path);
                return Err(error);
            }
        };
        if !metadata.file_type().is_socket() || metadata.uid() != Uid::effective().as_raw() {
            drop(listener);
            let _ = fs::remove_file(&self.socket_path);
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "bound AYUI IPC socket failed its ownership/type check",
            ));
        }

        Ok(listener)
    }

    /// Authenticate the connecting process using Linux SO_PEERCRED.
    fn peer_is_same_uid(stream: &UnixStream) -> bool {
        getsockopt(stream, PeerCredentials)
            .map(|credentials| credentials.uid() == Uid::effective().as_raw())
            .unwrap_or(false)
    }

    pub fn start_listener(&self, state_handler: Arc<Mutex<crate::state::AweuiState>>) {
        let socket_path = self.socket_path.clone();
        thread::spawn(move || {
            let server = IpcServer { socket_path };
            let listener = match server.bind() {
                Ok(listener) => listener,
                Err(error) => {
                    eprintln!("AYUI IPC bind failed: {error}");
                    return;
                }
            };

            for incoming in listener.incoming() {
                let mut stream = match incoming {
                    Ok(stream) => stream,
                    Err(error) => {
                        eprintln!("AYUI IPC accept failed: {error}");
                        continue;
                    }
                };

                if !Self::peer_is_same_uid(&stream) {
                    eprintln!("AYUI IPC rejected connection from a different uid");
                    continue;
                }

                let mut buffer = [0u8; 8192];
                let Ok(length) = stream.read(&mut buffer) else {
                    continue;
                };
                if length == 0 {
                    continue;
                }

                let Ok(request) = serde_json::from_slice::<IpcRequest>(&buffer[..length]) else {
                    continue;
                };
                let response = Self::handle_request(request, &state_handler);
                if let Ok(bytes) = serde_json::to_vec(&response) {
                    let _ = stream.write_all(&bytes);
                }
            }
        });
    }

    fn handle_request(
        request: IpcRequest,
        state_arc: &Arc<Mutex<crate::state::AweuiState>>,
    ) -> IpcResponse {
        let mut state = state_arc.lock().unwrap();
        match request {
            IpcRequest::GetStatus => IpcResponse::Success("AYUI Active".into()),
            IpcRequest::GetWorkspaces => IpcResponse::Workspaces(
                state
                    .workspaces
                    .workspaces
                    .iter()
                    .map(|workspace| workspace.name.clone())
                    .collect(),
            ),
            IpcRequest::SwitchWorkspace(index) => {
                state.workspaces.switch_to(index);
                IpcResponse::Success(format!("Switched to workspace {}", index + 1))
            }
            IpcRequest::LaunchApp(app) => match state.session.launch_app(&app) {
                Ok(()) => IpcResponse::Success(format!("Launched {app}")),
                Err(error) => IpcResponse::Error(error),
            },
            IpcRequest::GetConfig => IpcResponse::Config(
                toml::to_string_pretty(&state.config).unwrap_or_default(),
            ),
            IpcRequest::SetConfig(config) => match toml::from_str(&config) {
                Ok(config) => {
                    state.config = config;
                    let _ = state.config.save();
                    IpcResponse::Success("Configuration updated".into())
                }
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

pub fn send_ipc_request(socket_path: &str, request: IpcRequest) -> Result<IpcResponse, String> {
    let mut stream = UnixStream::connect(socket_path).map_err(|error| error.to_string())?;
    let bytes = serde_json::to_vec(&request).map_err(|error| error.to_string())?;
    stream.write_all(&bytes).map_err(|error| error.to_string())?;

    let mut buffer = [0u8; 8192];
    let length = stream.read(&mut buffer).map_err(|error| error.to_string())?;
    if length == 0 {
        return Err("AYUI IPC server closed the connection without a response".into());
    }
    serde_json::from_slice(&buffer[..length]).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use std::path::PathBuf;

    fn private_test_dir(label: &str) -> PathBuf {
        let directory = std::env::temp_dir().join(format!(
            "aweui-ipc-{label}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700)).unwrap();
        directory
    }

    #[test]
    fn socket_path_uses_private_runtime_subdirectory() {
        let path = resolve_socket_path(Some("/run/user/1000"), 1000);
        assert_eq!(path, "/run/user/1000/aweui/aweui-ipc.sock");
    }

    #[test]
    fn socket_path_falls_back_to_uid_runtime_directory() {
        let path = resolve_socket_path(None, 1001);
        assert_eq!(path, "/run/user/1001/aweui/aweui-ipc.sock");
    }

    #[test]
    fn socket_path_ignores_empty_or_relative_runtime_directory() {
        assert_eq!(
            resolve_socket_path(Some(""), 1002),
            "/run/user/1002/aweui/aweui-ipc.sock"
        );
        assert_eq!(
            resolve_socket_path(Some("relative/runtime"), 1003),
            "/run/user/1003/aweui/aweui-ipc.sock"
        );
    }

    #[test]
    fn bind_removes_a_stale_socket_but_not_a_live_listener() {
        let directory = private_test_dir("stale");
        let path = directory.join("aweui-ipc.sock");
        let stale_listener = UnixListener::bind(&path).unwrap();
        drop(stale_listener);

        let server = IpcServer::new(path.to_str().unwrap());
        let listener = server.bind().expect("stale socket should be reclaimed");
        assert!(fs::symlink_metadata(&path).unwrap().file_type().is_socket());
        drop(listener);
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn bind_refuses_to_replace_a_live_listener() {
        let directory = private_test_dir("active");
        let path = directory.join("aweui-ipc.sock");
        let active_listener = UnixListener::bind(&path).unwrap();
        let server = IpcServer::new(path.to_str().unwrap());

        let error = match server.bind() {
            Ok(listener) => {
                drop(listener);
                panic!("a second AYUI listener must not replace the active socket");
            }
            Err(error) => error,
        };
        assert_eq!(error.kind(), io::ErrorKind::AddrInUse);
        assert!(UnixStream::connect(&path).is_ok());

        drop(active_listener);
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn bind_never_removes_a_non_socket_path() {
        let directory = private_test_dir("regular-file");
        let path = directory.join("aweui-ipc.sock");
        fs::write(&path, b"not a socket").unwrap();
        let server = IpcServer::new(path.to_str().unwrap());

        let error = match server.bind() {
            Ok(listener) => {
                drop(listener);
                panic!("a regular file must not be replaced by the IPC socket");
            }
            Err(error) => error,
        };
        assert_eq!(error.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(fs::read(&path).unwrap(), b"not a socket");

        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn bind_sets_owner_only_socket_permissions() {
        let directory = private_test_dir("permissions");
        let path = directory.join("aweui-ipc.sock");
        let server = IpcServer::new(path.to_str().unwrap());
        let listener = server.bind().expect("private runtime directory should bind");

        let socket_mode = fs::symlink_metadata(&path).unwrap().permissions().mode() & 0o777;
        let directory_mode = fs::symlink_metadata(&directory).unwrap().permissions().mode() & 0o777;
        assert_eq!(socket_mode, 0o600);
        assert_eq!(directory_mode, 0o700);

        drop(listener);
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn bind_rejects_a_non_private_directory_without_changing_it() {
        let directory = std::env::temp_dir().join(format!(
            "aweui-ipc-unsafe-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&directory);
        fs::create_dir_all(&directory).unwrap();
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o755)).unwrap();
        let path = directory.join("aweui-ipc.sock");
        let server = IpcServer::new(path.to_str().unwrap());

        let error = match server.bind() {
            Ok(listener) => {
                drop(listener);
                panic!("world-readable runtime directory must be rejected");
            }
            Err(error) => error,
        };
        assert_eq!(error.kind(), io::ErrorKind::PermissionDenied);
        let mode = fs::symlink_metadata(&directory).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o755, "existing directory permissions must not be changed");

        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn bind_rejects_a_symlink_runtime_directory() {
        let target = private_test_dir("symlink-target");
        let link = std::env::temp_dir().join(format!(
            "aweui-ipc-symlink-{}",
            std::process::id()
        ));
        let _ = fs::remove_file(&link);
        symlink(&target, &link).unwrap();
        let path = link.join("aweui-ipc.sock");
        let server = IpcServer::new(path.to_str().unwrap());

        let error = match server.bind() {
            Ok(listener) => {
                drop(listener);
                panic!("symlink runtime directory must be rejected");
            }
            Err(error) => error,
        };
        assert_eq!(error.kind(), io::ErrorKind::PermissionDenied);

        let _ = fs::remove_file(&link);
        let _ = fs::remove_dir_all(&target);
    }

    #[test]
    fn bind_creates_a_private_socket_directory_below_runtime_dir() {
        let runtime_dir = private_test_dir("runtime-base");
        let socket_path = resolve_socket_path(
            Some(runtime_dir.to_str().unwrap()),
            Uid::effective().as_raw(),
        );
        let socket_parent = Path::new(&socket_path).parent().unwrap();
        assert!(!socket_parent.exists());

        let server = IpcServer::new(&socket_path);
        let listener = server.bind().expect("dedicated IPC directory should be created");
        let directory_mode =
            fs::symlink_metadata(socket_parent).unwrap().permissions().mode() & 0o777;
        let socket_mode =
            fs::symlink_metadata(&socket_path).unwrap().permissions().mode() & 0o777;

        assert_eq!(directory_mode, 0o700);
        assert_eq!(socket_mode, 0o600);

        drop(listener);
        let _ = fs::remove_dir_all(&runtime_dir);
    }

    #[test]
    fn peer_credentials_accept_the_current_effective_uid() {
        let directory = private_test_dir("peer-credentials");
        let path = directory.join("aweui-ipc.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let client = UnixStream::connect(&path).unwrap();
        let (server_stream, _) = listener.accept().unwrap();

        assert!(IpcServer::peer_is_same_uid(&server_stream));

        drop(client);
        drop(server_stream);
        drop(listener);
        let _ = fs::remove_dir_all(&directory);
    }

    #[test]
    fn legacy_privileged_ipc_requests_are_rejected() {
        assert!(serde_json::from_str::<IpcRequest>(r#"{"LaunchCommand":"id"}"#).is_err());
        assert!(serde_json::from_str::<IpcRequest>(r#"{"PowerAction":"reboot"}"#).is_err());
    }
}
