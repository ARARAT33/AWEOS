use crate::launcher::{AppInfo, Launcher};
use crate::notifications::NotificationDaemon;
use crate::shell::Panel;
use crate::theme::Theme;
use crate::wm::WindowManager;
use crate::workspaces::WorkspaceManager;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Overlay { None, Launcher, ControlCenter, Notifications, WindowOverview, Power }

pub struct DesktopShell {
    pub theme: Theme,
    pub panel: Panel,
    pub overlay: Overlay,
    pub search_query: String,
}

impl DesktopShell {
    pub fn new(theme_name:&str, panel_height:u32, panel_position:&str)->Self {
        Self { theme:Theme::from_name(theme_name), panel:Panel::new(panel_height,panel_position), overlay:Overlay::None, search_query:String::new() }
    }
    pub fn toggle_launcher(&mut self){ self.overlay=if self.overlay==Overlay::Launcher{Overlay::None}else{Overlay::Launcher}; }
    pub fn toggle_control_center(&mut self){ self.overlay=if self.overlay==Overlay::ControlCenter{Overlay::None}else{Overlay::ControlCenter}; }
    pub fn toggle_notifications(&mut self){ self.overlay=if self.overlay==Overlay::Notifications{Overlay::None}else{Overlay::Notifications}; }
    pub fn show_overview(&mut self){ self.overlay=Overlay::WindowOverview; }
    pub fn show_power(&mut self){ self.overlay=Overlay::Power; }
    pub fn close_overlay(&mut self){ self.overlay=Overlay::None; }
    pub fn search(&self, launcher:&Launcher)->Vec<AppInfo>{ launcher.search(&self.search_query) }
    pub fn visible_windows<'a>(&self,wm:&'a WindowManager,ws:&WorkspaceManager)->Vec<&'a crate::wm::Window>{
        wm.get_workspace_windows(ws.active_index)
    }
    pub fn notifications<'a>(&self,daemon:&'a NotificationDaemon)->Vec<&'a crate::notifications::Notification>{
        daemon.notifications.iter().collect()
    }
}
