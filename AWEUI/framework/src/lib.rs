use serde::{Deserialize, Serialize};

pub mod theme {
    pub const ACCENT_COLOR: &str = "#3b82f6";
    pub const BG_COLOR: &str = "#0f172a";
    pub const PANEL_BG: &str = "#1e293b";
    pub const TEXT_COLOR: &str = "#f8fafc";
    pub const BORDER_COLOR: &str = "#334155";
}

pub mod ipc {
    use super::*;
    use std::io::{Read, Write};
    use std::os::unix::net::UnixStream;
    use std::path::Path;
    use nix::unistd::Uid;

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

    /// Resolve the shared AYUI IPC endpoint for a session user.
    /// An absolute XDG_RUNTIME_DIR is preferred; invalid or missing values
    /// fall back to the conventional per-UID runtime directory.
    pub fn resolve_socket_path(runtime_dir: Option<&str>, uid: u32) -> String {
        if let Some(directory) = runtime_dir.filter(|value| !value.is_empty()) {
            let path = Path::new(directory);
            if path.is_absolute() {
                return path
                    .join("aweui")
                    .join("aweui-ipc.sock")
                    .to_string_lossy()
                    .into_owned();
            }
        }

        format!("/run/user/{uid}/aweui/aweui-ipc.sock")
    }

    /// Return the same endpoint used by the AYUI compositor.
    pub fn default_socket_path() -> String {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR").ok();
        resolve_socket_path(runtime_dir.as_deref(), Uid::effective().as_raw())
    }

    /// Check the live listener rather than merely checking whether a socket
    /// inode exists. A stale socket therefore reports as offline.
    pub fn socket_is_active() -> bool {
        UnixStream::connect(default_socket_path()).is_ok()
    }

    pub fn send_request(socket_path: &str, req: IpcRequest) -> Result<IpcResponse, String> {
        let mut stream = UnixStream::connect(socket_path).map_err(|e| format!("IPC Connection failed: {}", e))?;
        let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
        stream.write_all(&req_bytes).map_err(|e| e.to_string())?;

        let mut buf = vec![0u8; 4096];
        let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
        let resp: IpcResponse = serde_json::from_slice(&buf[..n]).map_err(|e| e.to_string())?;
        Ok(resp)
    }

    #[cfg(test)]
    mod tests {
        use super::resolve_socket_path;

        #[test]
        fn resolves_absolute_runtime_directory() {
            assert_eq!(
                resolve_socket_path(Some("/run/user/1000"), 1000),
                "/run/user/1000/aweui/aweui-ipc.sock"
            );
        }

        #[test]
        fn falls_back_for_missing_empty_and_relative_runtime_directories() {
            assert_eq!(
                resolve_socket_path(None, 1001),
                "/run/user/1001/aweui/aweui-ipc.sock"
            );
            assert_eq!(
                resolve_socket_path(Some(""), 1002),
                "/run/user/1002/aweui/aweui-ipc.sock"
            );
            assert_eq!(
                resolve_socket_path(Some("relative/path"), 1003),
                "/run/user/1003/aweui/aweui-ipc.sock"
            );
        }
    }
}

pub fn init() {
    println!("[AWEUI Framework] Native AWEUI Application Environment Initialized.");
}
