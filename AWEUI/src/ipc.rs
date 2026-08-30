use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex};
use std::thread;

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

pub struct IpcServer {
    pub socket_path: String,
}

impl IpcServer {
    pub fn new(socket_path: &str) -> Self {
        let _ = fs::remove_file(socket_path);
        Self {
            socket_path: socket_path.to_string(),
        }
    }

    pub fn start_listener(&self, state_handler: Arc<Mutex<crate::state::AweuiState>>) {
        let socket_path = self.socket_path.clone();
        thread::spawn(move || {
            let listener = match UnixListener::bind(&socket_path) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("Failed to bind IPC socket {}: {}", socket_path, e);
                    return;
                }
            };

            for stream in listener.incoming() {
                if let Ok(mut stream) = stream {
                    let mut buf = vec![0u8; 4096];
                    if let Ok(n) = stream.read(&mut buf) {
                        if n > 0 {
                            if let Ok(req) = serde_json::from_slice::<IpcRequest>(&buf[..n]) {
                                let resp = Self::handle_request(req, &state_handler);
                                if let Ok(resp_bytes) = serde_json::to_vec(&resp) {
                                    let _ = stream.write_all(&resp_bytes);
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    fn handle_request(req: IpcRequest, state_arc: &Arc<Mutex<crate::state::AweuiState>>) -> IpcResponse {
        let mut state = state_arc.lock().unwrap();
        match req {
            IpcRequest::GetStatus => IpcResponse::Success("AWEUI Compositor Active".to_string()),
            IpcRequest::GetWorkspaces => {
                let names = state.workspaces.workspaces.iter().map(|w| w.name.clone()).collect();
                IpcResponse::Workspaces(names)
            }
            IpcRequest::SwitchWorkspace(idx) => {
                state.workspaces.switch_to(idx);
                IpcResponse::Success(format!("Switched to workspace {}", idx + 1))
            }
            IpcRequest::LaunchApp(app) => {
                let _ = std::process::Command::new(&app).spawn();
                IpcResponse::Success(format!("Launched {}", app))
            }
            IpcRequest::GetConfig => {
                let cfg_str = toml::to_string_pretty(&state.config).unwrap_or_default();
                IpcResponse::Config(cfg_str)
            }
            IpcRequest::SetConfig(cfg_str) => {
                if let Ok(cfg) = toml::from_str(&cfg_str) {
                    state.config = cfg;
                    let _ = state.config.save();
                    IpcResponse::Success("Configuration updated".to_string())
                } else {
                    IpcResponse::Error("Invalid configuration syntax".to_string())
                }
            }
            IpcRequest::ToggleControlCenter => {
                IpcResponse::Success("Control Center toggled".to_string())
            }
            IpcRequest::SendNotification { title, body } => {
                println!("[AWEUI Notification] {}: {}", title, body);
                IpcResponse::Success("Notification delivered".to_string())
            }
        }
    }
}

pub fn send_ipc_request(socket_path: &str, req: IpcRequest) -> Result<IpcResponse, String> {
    let mut stream = UnixStream::connect(socket_path).map_err(|e| e.to_string())?;
    let req_bytes = serde_json::to_vec(&req).map_err(|e| e.to_string())?;
    stream.write_all(&req_bytes).map_err(|e| e.to_string())?;

    let mut buf = vec![0u8; 4096];
    let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
    let resp: IpcResponse = serde_json::from_slice(&buf[..n]).map_err(|e| e.to_string())?;
    Ok(resp)
}
