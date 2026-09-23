use std::sync::{Arc, Mutex};
use crate::config::AweuiConfig;
use crate::desktop::DesktopShell;
use crate::notifications::NotificationDaemon;
use crate::ipc::IpcServer;
use crate::session::SessionManager;
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
    pub session: SessionManager,
    pub notifications: NotificationDaemon,
    pub desktop: DesktopShell,
    pub running: bool,
}

impl AweuiState {
    pub fn new() -> Self {
        let config = AweuiConfig::load();
        let wm = WindowManager::new(config.wm.clone());
        let workspaces = WorkspaceManager::new(config.wm.workspace_count);
        let ipc_server = Arc::new(Mutex::new(IpcServer::new("/tmp/aweui-ipc.sock")));
        let desktop = DesktopShell::new(&config.desktop.theme, config.panel.height, &config.panel.position);
        Self {
            config,
            wm,
            workspaces,
            ipc_server,
            session: SessionManager::new(),
            notifications: NotificationDaemon::new(),
            desktop,
            running: true,
        }
    }
}
