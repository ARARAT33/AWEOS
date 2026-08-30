pub struct InputManager {
    pub keymap: String,
}

impl InputManager {
    pub fn new() -> Self {
        Self {
            keymap: "us".to_string(),
        }
    }

    pub fn handle_key_code(&mut self, _state: &mut crate::state::AweuiState, key_code: u32, is_pressed: bool) {
        if is_pressed && key_code == 28 {
            println!("[InputManager] Key Enter Pressed");
        }
    }

    pub fn handle_pointer_button(&mut self, _state: &mut crate::state::AweuiState, button: u32, is_pressed: bool) {
        if is_pressed {
            println!("[InputManager] Pointer Button {} Pressed", button);
        }
    }
}
