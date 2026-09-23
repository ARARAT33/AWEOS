use std::{os::unix::io::OwnedFd, sync::{Arc, Mutex}, time::Instant};

use smithay::{
    backend::{
        input::{InputEvent, KeyboardKeyEvent},
        renderer::{
            element::{surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement}, Kind},
            gles::GlesRenderer,
            utils::{draw_render_elements, on_commit_buffer_handler},
            Color32F, Frame, Renderer,
        },
        winit::{self, WinitEvent},
    },
    delegate_compositor, delegate_data_device, delegate_seat, delegate_shm, delegate_xdg_shell,
    input::{keyboard::FilterResult, Seat, SeatHandler, SeatState},
    reexports::wayland_server::{protocol::wl_seat, Display},
    utils::{Rectangle, Serial, Transform},
    wayland::{
        buffer::BufferHandler,
        compositor::{with_surface_tree_downward, CompositorClientState, CompositorHandler, CompositorState, SurfaceAttributes, TraversalAction},
        selection::{data_device::{ClientDndGrabHandler, DataDeviceHandler, DataDeviceState, ServerDndGrabHandler}, SelectionHandler},
        shell::xdg::{PopupSurface, PositionerState, ToplevelSurface, XdgShellHandler, XdgShellState},
        shm::{ShmHandler, ShmState},
    },
};
use wayland_protocols::xdg::shell::server::xdg_toplevel;
use wayland_server::{
    backend::{ClientData, ClientId, DisconnectReason},
    protocol::{wl_buffer, wl_surface::{self, WlSurface}},
    Client, ListeningSocket,
};

use crate::state::AweuiState;

pub struct ManagedWindow {
    pub surface: ToplevelSurface,
    pub loc: (i32, i32),
}

pub struct AyuiCompositor {
    pub ui: Arc<Mutex<AweuiState>>,
    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub shm_state: ShmState,
    pub seat_state: SeatState<Self>,
    pub data_device_state: DataDeviceState,
    pub seat: Seat<Self>,
    pub windows: Vec<ManagedWindow>,
}

impl BufferHandler for AyuiCompositor {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl XdgShellHandler for AyuiCompositor {
    fn xdg_shell_state(&mut self) -> &mut XdgShellState { &mut self.xdg_shell_state }

    fn new_toplevel(&mut self, surface: ToplevelSurface) {
        let (title, app_id) = surface.with_pending_state(|state| {
            state.states.set(xdg_toplevel::State::Activated);
            (state.title.clone().unwrap_or_else(|| "AWE Application".into()),
             state.app_id.clone().unwrap_or_else(|| "unknown".into()))
        });
        surface.send_configure();
        if let Ok(mut ui) = self.ui.lock() {
            ui.wm.create_window(&title, &app_id);
        }
        let index = self.windows.len();
        self.windows.push(ManagedWindow { surface, loc: (40 + (index as i32 * 32) % 360, 56 + (index as i32 * 28) % 220) });
        tracing::info!(%title, %app_id, "AYUI: new Wayland toplevel");
    }

    fn new_popup(&mut self, _surface: PopupSurface, _positioner: PositionerState) {}
    fn grab(&mut self, _surface: PopupSurface, _seat: wl_seat::WlSeat, _serial: Serial) {}
    fn reposition_request(&mut self, _surface: PopupSurface, _positioner: PositionerState, _token: u32) {}
}

impl SelectionHandler for AyuiCompositor { type SelectionUserData = (); }

impl DataDeviceHandler for AyuiCompositor {
    fn data_device_state(&self) -> &DataDeviceState { &self.data_device_state }
}
impl ClientDndGrabHandler for AyuiCompositor {}
impl ServerDndGrabHandler for AyuiCompositor {
    fn send(&mut self, _mime_type: String, _fd: OwnedFd, _seat: Seat<Self>) {}
}

impl CompositorHandler for AyuiCompositor {
    fn compositor_state(&mut self) -> &mut CompositorState { &mut self.compositor_state }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        &client.get_data::<ClientState>().expect("AYUI client state missing").compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        on_commit_buffer_handler::<Self>(surface);
    }
}

impl ShmHandler for AyuiCompositor {
    fn shm_state(&self) -> &ShmState { &self.shm_state }
}

impl SeatHandler for AyuiCompositor {
    type KeyboardFocus = WlSurface;
    type PointerFocus = WlSurface;
    type TouchFocus = WlSurface;

    fn seat_state(&mut self) -> &mut SeatState<Self> { &mut self.seat_state }
    fn focus_changed(&mut self, _seat: &Seat<Self>, _focused: Option<&WlSurface>) {}
    fn cursor_image(&mut self, _seat: &Seat<Self>, _image: smithay::input::pointer::CursorImageStatus) {}
}

#[derive(Default)]
struct ClientState { compositor_state: CompositorClientState }

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}

fn send_frames_surface_tree(surface: &wl_surface::WlSurface, time: u32) {
    with_surface_tree_downward(
        surface, (), |_, _, &()| TraversalAction::DoChildren(()),
        |_surf, states, &()| {
            for callback in states.cached_state.get::<SurfaceAttributes>().current().frame_callbacks.drain(..) {
                callback.done(time);
            }
        },
        |_, _, &()| true,
    );
}

pub fn run(ui: Arc<Mutex<AweuiState>>) -> Result<(), Box<dyn std::error::Error>> {
    let mut display: Display<AyuiCompositor> = Display::new()?;
    let dh = display.handle();

    let compositor_state = CompositorState::new::<AyuiCompositor>(&dh);
    let shm_state = ShmState::new::<AyuiCompositor>(&dh, vec![]);
    let mut seat_state = SeatState::new();
    let seat = seat_state.new_wl_seat(&dh, "ayui");
    let mut state = AyuiCompositor {
        ui,
        compositor_state,
        xdg_shell_state: XdgShellState::new::<AyuiCompositor>(&dh),
        shm_state,
        seat_state,
        data_device_state: DataDeviceState::new::<AyuiCompositor>(&dh),
        seat,
        windows: Vec::new(),
    };

    let (mut backend, mut winit) = winit::init::<GlesRenderer>()?;
    let listener = ListeningSocket::bind_auto("wayland", 1..32)?;
    let socket_name = listener.socket_name().and_then(|s| s.to_str()).unwrap_or("wayland-?");
    std::env::set_var("WAYLAND_DISPLAY", socket_name);
    std::env::set_var("XDG_SESSION_TYPE", "wayland");
    std::env::set_var("XDG_CURRENT_DESKTOP", "AYUI");
    println!("AYUI Wayland compositor listening on {socket_name}");

    let keyboard = state.seat.add_keyboard(Default::default(), 200, 200)?;
    let start = Instant::now();
    let mut clients = Vec::new();

    loop {
        let status = winit.dispatch_new_events(|event| match event {
            WinitEvent::CloseRequested => {
                if let Ok(mut ui) = state.ui.lock() { ui.running = false; }
            }
            WinitEvent::Input(InputEvent::Keyboard { event }) => {
                keyboard.input::<(), _>(&mut state, event.key_code(), event.state(), 0.into(), 0,
                    |_, _, _| FilterResult::Forward);
            }
            WinitEvent::Input(InputEvent::PointerMotionAbsolute { .. }) => {
                if let Some(surface) = state.xdg_shell_state.toplevel_surfaces().iter().next().cloned() {
                    keyboard.set_focus(&mut state, Some(surface.wl_surface().clone()), 0.into());
                }
            }
            _ => {}
        });

        if matches!(status, ::winit::platform::pump_events::PumpStatus::Exit(_)) { break; }

        let size = backend.window_size();
        let damage = Rectangle::from_size(size);
        {
            let (renderer, mut framebuffer) = backend.bind()?;
            let elements = state.windows.iter().filter(|window| window.surface.alive()).flat_map(|window| {
                render_elements_from_surface_tree(renderer, window.surface.wl_surface(), window.loc, 1.0, 1.0, Kind::Unspecified)
            }).collect::<Vec<WaylandSurfaceRenderElement<GlesRenderer>>>();

            let mut frame = renderer.render(&mut framebuffer, size, Transform::Flipped180)?;
            frame.clear(Color32F::new(0.035, 0.04, 0.055, 1.0), &[damage])?;
            draw_render_elements(&mut frame, 1.0, &elements, &[damage])?;
            let _ = frame.finish()?;

            let now = start.elapsed().as_millis() as u32;
            for surface in state.xdg_shell_state.toplevel_surfaces() {
                send_frames_surface_tree(surface.wl_surface(), now);
            }

            if let Some(stream) = listener.accept()? {
                let client = display.handle().insert_client(stream, Arc::new(ClientState::default()))?;
                clients.push(client);
            }
            display.dispatch_clients(&mut state)?;
            display.flush_clients()?;
        }
        backend.submit(Some(&[damage]))?;

        if state.ui.lock().map(|ui| !ui.running).unwrap_or(true) { break; }
    }

    Ok(())
}

delegate_xdg_shell!(AyuiCompositor);
delegate_compositor!(AyuiCompositor);
delegate_shm!(AyuiCompositor);
delegate_seat!(AyuiCompositor);
delegate_data_device!(AyuiCompositor);
