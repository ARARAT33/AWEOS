#[derive(Debug, Clone)]
pub struct Output {
    pub name: String,
    pub width: i32,
    pub height: i32,
    pub refresh_mhz: i32,
    pub scale: i32,
}

pub struct OutputManager {
    pub outputs: Vec<Output>,
}

impl OutputManager {
    pub fn new() -> Self {
        Self { outputs: Vec::new() }
    }

    pub fn create_output(
        &mut self,
        name: &str,
        width: i32,
        height: i32,
        refresh_mhz: i32,
        scale: i32,
    ) -> Output {
        let output = Output {
            name: name.to_string(),
            width,
            height,
            refresh_mhz,
            scale,
        };
        self.outputs.push(output.clone());
        output
    }
}
