pub struct InputManager { pub keymap: String, pub pointer_x: f64, pub pointer_y: f64 }

impl InputManager {
    pub fn new() -> Self { Self { keymap: "us".into(), pointer_x: 0.0, pointer_y: 0.0 } }

    pub fn handle_key_code(&mut self, state: &mut crate::state::AweuiState, key_code:u32, is_pressed:bool) {
        if !is_pressed { return; }
        match key_code {
            1 => { let _ = crate::session::SessionManager::power_action("logout"); state.running=false; }
            59..=68 => {
                let index=(key_code-59) as usize;
                if index < state.workspaces.workspaces.len() { state.workspaces.switch_to(index); }
            }
            28 => println!("[AYUI] Enter"),
            _ => {}
        }
    }
    pub fn handle_pointer_motion(&mut self,x:f64,y:f64){ self.pointer_x=x; self.pointer_y=y; }
    pub fn handle_pointer_button(&mut self,state:&mut crate::state::AweuiState,button:u32,is_pressed:bool){
        if is_pressed && button==1 {
            if let Some(id)=state.wm.active_window_id { state.wm.set_focus(id); }
        }
    }
}
