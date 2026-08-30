use std::sync::{Arc, Mutex};
use crate::config::AweuiConfig;
use crate::ipc::IpcServer;
use crate::wm::WindowManager;
use crate::workspaces::WorkspaceManager;

pub struct ClientState {
    pub id: usize,
}

pub struct AweuiState {
    pub config: AweuiConfig,
    pub wm: WindowManager,
    pub workspaces: WorkspaceManager,
    pub ipc_server: Arc<Mutex<IpcServer>>,
    pub running: bool,
}

impl AweuiState {
    pub fn new() -> Self {
        let config = AweuiConfig::load();
        let wm = WindowManager::new(config.wm.clone());
        let workspaces = WorkspaceManager::new(config.wm.workspace_count);
        let ipc_server = Arc::new(Mutex::new(IpcServer::new("/tmp/aweui-ipc.sock")));

        Self {
            config,
            wm,
            workspaces,
            ipc_server,
            running: true,
        }
    }
}
