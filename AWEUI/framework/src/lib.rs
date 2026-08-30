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

pub fn init() {
    println!("[AWEUI Framework] Native AWEUI Application Environment Initialized.");
}
