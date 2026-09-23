#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BackendMode { DrmKms, Winit, Headless }

#[derive(Debug, Clone, Copy)]
pub struct FrameStats { pub frame: u64, pub width: u32, pub height: u32 }

pub struct RenderManager {
    pub mode: BackendMode,
    pub width: u32,
    pub height: u32,
    pub frame: u64,
}

impl RenderManager {
    pub fn new(mode: BackendMode, width: u32, height: u32) -> Self {
        Self { mode, width, height, frame: 0 }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width.max(1);
        self.height = height.max(1);
    }

    pub fn render_frame(&mut self, _clear_color: [f32; 4]) -> Result<FrameStats, String> {
        self.frame = self.frame.wrapping_add(1);
        Ok(FrameStats { frame: self.frame, width: self.width, height: self.height })
    }

    pub fn backend_name(&self) -> &'static str {
        match self.mode { BackendMode::DrmKms => "drm-kms", BackendMode::Winit => "winit", BackendMode::Headless => "headless" }
    }
}
