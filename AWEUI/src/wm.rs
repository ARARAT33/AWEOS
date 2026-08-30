#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowGeometry {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowState {
    Normal,
    Maximized,
    Minimized,
    Fullscreen,
    Tiled,
}

#[derive(Debug, Clone)]
pub struct Window {
    pub id: usize,
    pub title: String,
    pub app_id: String,
    pub geometry: WindowGeometry,
    pub state: WindowState,
    pub workspace_id: usize,
    pub is_focused: bool,
    pub is_always_on_top: bool,
    pub saved_geometry: Option<WindowGeometry>,
}

pub struct WindowManager {
    pub windows: Vec<Window>,
    pub active_window_id: Option<usize>,
    pub next_id: usize,
    pub default_mode: String,
    pub gap_size: u32,
    pub border_width: u32,
}

impl WindowManager {
    pub fn new(cfg: crate::config::WmConfig) -> Self {
        Self {
            windows: Vec::new(),
            active_window_id: None,
            next_id: 1,
            default_mode: cfg.default_mode,
            gap_size: cfg.gap_size,
            border_width: cfg.border_width,
        }
    }

    pub fn create_window(&mut self, title: &str, app_id: &str) -> usize {
        let id = self.next_id;
        self.next_id += 1;

        let win = Window {
            id,
            title: title.to_string(),
            app_id: app_id.to_string(),
            geometry: WindowGeometry {
                x: 100 + (id as i32 * 20) % 400,
                y: 100 + (id as i32 * 20) % 300,
                width: 800,
                height: 600,
            },
            state: WindowState::Normal,
            workspace_id: 0,
            is_focused: true,
            is_always_on_top: false,
            saved_geometry: None,
        };

        self.windows.push(win);
        self.set_focus(id);
        id
    }

    pub fn move_window(&mut self, id: usize, dx: i32, dy: i32) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            win.geometry.x += dx;
            win.geometry.y += dy;
        }
    }

    pub fn resize_window(&mut self, id: usize, width: u32, height: u32) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            win.geometry.width = width.max(100);
            win.geometry.height = height.max(100);
        }
    }

    pub fn snap_window_to_edge(&mut self, id: usize, edge: &str, screen_w: u32, screen_h: u32) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            let panel_offset = 32;
            let available_h = screen_h - panel_offset;
            match edge {
                "left" => {
                    win.geometry = WindowGeometry {
                        x: 0,
                        y: panel_offset as i32,
                        width: screen_w / 2,
                        height: available_h,
                    };
                    win.state = WindowState::Tiled;
                }
                "right" => {
                    win.geometry = WindowGeometry {
                        x: (screen_w / 2) as i32,
                        y: panel_offset as i32,
                        width: screen_w / 2,
                        height: available_h,
                    };
                    win.state = WindowState::Tiled;
                }
                "top" => {
                    win.geometry = WindowGeometry {
                        x: 0,
                        y: panel_offset as i32,
                        width: screen_w,
                        height: available_h / 2,
                    };
                    win.state = WindowState::Tiled;
                }
                "bottom" => {
                    win.geometry = WindowGeometry {
                        x: 0,
                        y: (panel_offset + available_h / 2) as i32,
                        width: screen_w,
                        height: available_h / 2,
                    };
                    win.state = WindowState::Tiled;
                }
                _ => {}
            }
        }
    }

    pub fn maximize_window(&mut self, id: usize, screen_w: u32, screen_h: u32) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            if win.state != WindowState::Maximized {
                win.saved_geometry = Some(win.geometry.clone());
                win.geometry = WindowGeometry {
                    x: 0,
                    y: 32,
                    width: screen_w,
                    height: screen_h - 32,
                };
                win.state = WindowState::Maximized;
            } else if let Some(saved) = win.saved_geometry.take() {
                win.geometry = saved;
                win.state = WindowState::Normal;
            }
        }
    }

    pub fn minimize_window(&mut self, id: usize) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            win.state = WindowState::Minimized;
            win.is_focused = false;
        }
    }

    pub fn restore_window(&mut self, id: usize) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == id) {
            win.state = WindowState::Normal;
            self.set_focus(id);
        }
    }

    pub fn close_window(&mut self, id: usize) {
        self.windows.retain(|w| w.id != id);
        if self.active_window_id == Some(id) {
            self.active_window_id = self.windows.last().map(|w| w.id);
        }
    }

    pub fn set_focus(&mut self, id: usize) {
        for win in &mut self.windows {
            win.is_focused = win.id == id;
        }
        self.active_window_id = Some(id);
    }

    pub fn move_window_to_workspace(&mut self, window_id: usize, workspace_id: usize) {
        if let Some(win) = self.windows.iter_mut().find(|w| w.id == window_id) {
            win.workspace_id = workspace_id;
        }
    }

    pub fn get_workspace_windows(&self, workspace_id: usize) -> Vec<&Window> {
        self.windows
            .iter()
            .filter(|w| w.workspace_id == workspace_id && w.state != WindowState::Minimized)
            .collect()
    }
}
