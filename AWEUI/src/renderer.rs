pub enum BackendMode {
    DrmKms,
    Winit,
    Headless,
}

pub struct RenderManager {
    pub mode: BackendMode,
    pub width: u32,
    pub height: u32,
}

impl RenderManager {
    pub fn new(mode: BackendMode, width: u32, height: u32) -> Self {
        Self { mode, width, height }
    }

    pub fn render_frame(&mut self, clear_color: [f32; 4]) -> Result<(), String> {
        println!("[RenderManager] Rendering frame {}x{} with clear color {:?}", self.width, self.height, clear_color);
        Ok(())
    }
}
