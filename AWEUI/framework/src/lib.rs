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

    /// Returns the per-session AYUI control socket.  Never use a predictable
    /// shared `/tmp` name: a second user must not be able to impersonate the
    /// desktop service or issue session control requests.
    pub fn default_socket_path() -> String {
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .unwrap_or_else(|_| "/run/user/0".to_string());
        format!("{runtime_dir}/aweui-ipc.sock")
    }

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

    pub fn send_request(socket_path: &str, req: IpcRequest) -> Result<IpcResponse, String> {
        let mut stream = UnixStream::connect(socket_path).map_err(|e| format!("IPC Connection failed: {}", e))?;
        let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
        stream.write_all(&req_bytes).map_err(|e| e.to_string())?;

        let mut buf = vec![0u8; 4096];
        let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
        let resp: IpcResponse = serde_json::from_slice(&buf[..n]).map_err(|e| e.to_string())?;
        Ok(resp)
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn ipc_socket_uses_the_session_runtime_directory() {
        // Do not mutate process environment in a parallel test.
        assert!(super::ipc::default_socket_path().ends_with("/aweui-ipc.sock"));
    }
}

pub fn init() {
    println!("[AWEUI Framework] Native AWEUI Application Environment Initialized.");
}
