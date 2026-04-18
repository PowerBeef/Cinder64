use gopher64::{device, ui};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, mpsc};
use std::thread::JoinHandle;
use std::time::Duration;

const VERSION: &[u8] = b"gopher64-cinder64-bridge 0.2.0\0";

#[derive(Clone)]
struct HostSurfaceDescriptor {
    window_handle: usize,
    view_handle: usize,
    width: i32,
    height: i32,
    backing_scale_factor: f64,
}

impl HostSurfaceDescriptor {
    fn pixel_width(&self) -> u32 {
        ((self.width as f64 * self.backing_scale_factor).round() as i64).max(1) as u32
    }

    fn pixel_height(&self) -> u32 {
        ((self.height as f64 * self.backing_scale_factor).round() as i64).max(1) as u32
    }
}

#[derive(Clone, Default)]
struct RuntimeStatus {
    active: bool,
    running: bool,
    paused: bool,
    shutdown_requested: bool,
    frame_rate: f64,
    last_error: Option<String>,
}

#[derive(Clone)]
struct RuntimeDirectories {
    config_dir: PathBuf,
    data_dir: PathBuf,
    cache_dir: PathBuf,
}

#[derive(Clone)]
struct RuntimeSettings {
    fullscreen: bool,
    mute_audio: bool,
    speed_percent: i32,
    upscale_multiplier: i32,
    integer_scaling: bool,
    crt_filter: bool,
    active_save_slot: i32,
}

#[derive(Copy, Clone)]
struct EmbeddedWindowHandle(usize);

impl EmbeddedWindowHandle {
    fn as_ptr(self) -> *mut std::ffi::c_void {
        self.0 as *mut std::ffi::c_void
    }
}

pub struct BridgeSession {
    surface: Option<HostSurfaceDescriptor>,
    current_rom_path: Option<PathBuf>,
    runtime_directories: Option<RuntimeDirectories>,
    settings: RuntimeSettings,
    renderer_name: CString,
    last_error: CString,
    frame_rate: f64,
    sdl_window: Option<EmbeddedWindowHandle>,
    runtime_status: Arc<Mutex<RuntimeStatus>>,
    emulation_thread: Option<JoinHandle<()>>,
    pump_tick_count: u64,
}

impl BridgeSession {
    fn new() -> Self {
        Self {
            surface: None,
            current_rom_path: None,
            runtime_directories: None,
            settings: RuntimeSettings {
                fullscreen: false,
                mute_audio: false,
                speed_percent: 100,
                upscale_multiplier: 2,
                integer_scaling: false,
                crt_filter: false,
                active_save_slot: 0,
            },
            renderer_name: CString::new("gopher64 + parallel-rdp (embedded)").unwrap(),
            last_error: CString::new("").unwrap(),
            frame_rate: 0.0,
            sdl_window: None,
            runtime_status: Arc::new(Mutex::new(RuntimeStatus::default())),
            emulation_thread: None,
            pump_tick_count: 0,
        }
    }

    fn set_error(&mut self, message: impl AsRef<str>) -> i32 {
        self.last_error = sanitize_c_string(message.as_ref());
        if let Ok(mut status) = self.runtime_status.lock() {
            status.last_error = Some(message.as_ref().to_string());
        }
        -1
    }

    fn clear_error(&mut self) {
        self.last_error = CString::new("").unwrap();
        if let Ok(mut status) = self.runtime_status.lock() {
            status.last_error = None;
        }
    }

    fn update_error_from_runtime(&mut self) {
        let runtime_error = self
            .runtime_status
            .lock()
            .ok()
            .and_then(|status| status.last_error.clone());
        if let Some(message) = runtime_error {
            self.last_error = sanitize_c_string(&message);
        }
    }

    fn has_active_runtime(&self) -> bool {
        self.emulation_thread.is_some()
            && self
                .runtime_status
                .lock()
                .map(|status| status.active)
                .unwrap_or(false)
    }
}

fn sanitize_c_string(message: &str) -> CString {
    CString::new(message.replace('\0', " ")).unwrap()
}

unsafe fn session_from_ptr<'a>(session: *mut BridgeSession) -> Result<&'a mut BridgeSession, i32> {
    session.as_mut().ok_or(-1)
}

fn c_string_from_ptr(value: *const c_char) -> Result<String, String> {
    if value.is_null() {
        return Err("The bridge received a null string pointer.".to_string());
    }

    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map(|text| text.to_string())
        .map_err(|_| "The bridge received a non-UTF8 string.".to_string())
}

fn normalize_upscale(value: i32) -> u32 {
    match value.clamp(1, 8) {
        1 => 1,
        2 | 3 => 2,
        4..=7 => 4,
        _ => 8,
    }
}

fn load_rom_contents(path: &Path) -> Result<Vec<u8>, String> {
    let result = catch_unwind(AssertUnwindSafe(|| device::get_rom_contents(path)));
    match result {
        Ok(Some(contents)) => Ok(contents),
        Ok(None) => Err(format!(
            "The ROM at {} is not a supported .z64, .v64, .n64, .zip, or .7z image.",
            path.display()
        )),
        Err(_) => Err(format!(
            "The embedded gopher64 loader rejected the ROM at {}.",
            path.display()
        )),
    }
}

fn ensure_runtime_directories(directories: &RuntimeDirectories) -> Result<(), String> {
    for directory in [
        &directories.config_dir,
        &directories.data_dir,
        &directories.cache_dir,
        &directories.data_dir.join("saves"),
        &directories.data_dir.join("states"),
    ] {
        std::fs::create_dir_all(directory)
            .map_err(|error| format!("Could not prepare {}: {error}", directory.display()))?;
    }
    Ok(())
}

fn spawn_runtime_thread(
    rom_contents: Vec<u8>,
    directories: RuntimeDirectories,
    settings: RuntimeSettings,
    embedded_window: EmbeddedWindowHandle,
    runtime_status: Arc<Mutex<RuntimeStatus>>,
    startup_signal: mpsc::Sender<Result<f64, String>>,
) -> JoinHandle<()> {
    std::thread::spawn(move || {
        let mut startup_signal = Some(startup_signal);
        let result = catch_unwind(AssertUnwindSafe(|| {
            ui::set_dirs_override(Some(ui::Dirs {
                config_dir: directories.config_dir.clone(),
                data_dir: directories.data_dir.clone(),
                cache_dir: directories.cache_dir.clone(),
            }));

            let mut device = device::Device::new();
            device.ui.video.window = embedded_window.as_ptr() as _;
            device.ui.video.fullscreen = settings.fullscreen;
            device.ui.audio.gain = if settings.mute_audio { 0.0 } else { 1.0 };
            device.ui.storage.save_state_slot = settings.active_save_slot.max(0) as u32;
            device.ui.config.video.fullscreen = settings.fullscreen;
            device.ui.config.video.upscale = normalize_upscale(settings.upscale_multiplier);
            device.ui.config.video.integer_scaling = settings.integer_scaling;
            device.ui.config.video.crt = settings.crt_filter;

            let game_settings = ui::gui::GameSettings {
                overclock: settings.speed_percent > 100,
                disable_expansion_pak: false,
                cheats: HashMap::new(),
                load_savestate_slot: None,
            };

            let runtime_status_for_ready = Arc::clone(&runtime_status);
            device::run_game_with_ready_hook(
                &mut device,
                &rom_contents,
                game_settings,
                |device| {
                    let frame_rate = if device.vi.frame_time > 0.0 {
                        1.0 / device.vi.frame_time
                    } else {
                        60.0
                    };

                    if let Ok(mut status) = runtime_status_for_ready.lock() {
                        status.active = true;
                        status.running = false;
                        status.paused = true;
                        status.shutdown_requested = false;
                        status.frame_rate = frame_rate;
                        status.last_error = None;
                    }

                    if let Some(signal) = startup_signal.take() {
                        let _ = signal.send(Ok(frame_rate));
                    }
                },
            );

            if let Some(message) = ui::video::last_close_error() {
                if let Ok(mut status) = runtime_status.lock() {
                    status.last_error = Some(message);
                }
            }
        }));

        let shutdown_requested = runtime_status
            .lock()
            .ok()
            .map(|status| status.shutdown_requested)
            .unwrap_or(false);
        let ready_was_reported = startup_signal.is_none();

        if let Ok(mut status) = runtime_status.lock() {
            status.active = false;
            status.running = false;
            status.paused = false;
            status.shutdown_requested = false;
            if ready_was_reported && !shutdown_requested && status.last_error.is_none() {
                status.last_error =
                    Some("The embedded gopher64 runtime exited unexpectedly after boot.".to_string());
            }
        }

        ui::set_dirs_override(None);

        match result {
            Ok(()) => {
                if let Some(signal) = startup_signal.take() {
                    let _ = signal.send(Err(
                        "The embedded gopher64 runtime exited before it reported readiness."
                            .to_string(),
                    ));
                }
            }
            Err(_) => {
                let message =
                    "The embedded gopher64 runtime panicked while executing the game loop."
                        .to_string();
                if let Ok(mut status) = runtime_status.lock() {
                    status.last_error = Some(message.clone());
                }
                if let Some(signal) = startup_signal.take() {
                    let _ = signal.send(Err(message));
                }
            }
        }
    })
}

fn stop_runtime(session: &mut BridgeSession) -> Result<(), String> {
    ui::video::set_hosted_mode(false);
    ui::input::reset_host_key_state();

    if session.emulation_thread.is_none() {
        if let Some(window) = session.sdl_window.take() {
            ui::video::destroy_embedded_window(window.as_ptr() as _);
        }
        session.sdl_window = None;
        session.current_rom_path = None;
        session.frame_rate = 0.0;
        return Ok(());
    }

    if let Ok(mut status) = session.runtime_status.lock() {
        status.shutdown_requested = true;
    }
    ui::video::request_shutdown();
    if let Some(thread) = session.emulation_thread.take() {
        thread
            .join()
            .map_err(|_| "The embedded gopher64 runtime panicked while shutting down.".to_string())?;
    }

    let shutdown_error = session
        .runtime_status
        .lock()
        .ok()
        .and_then(|status| status.last_error.clone());

    if let Some(window) = session.sdl_window.take() {
        ui::video::destroy_embedded_window(window.as_ptr() as _);
    }
    session.current_rom_path = None;
    session.frame_rate = 0.0;
    if let Ok(mut status) = session.runtime_status.lock() {
        status.active = false;
        status.running = false;
        status.paused = false;
        status.shutdown_requested = false;
        status.frame_rate = 0.0;
    }

    if let Some(message) = shutdown_error {
        return Err(message);
    }

    session.clear_error();
    Ok(())
}

#[no_mangle]
pub extern "C" fn cinder64_bridge_create_session() -> *mut BridgeSession {
    Box::into_raw(Box::new(BridgeSession::new()))
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_destroy_session(session: *mut BridgeSession) {
    if session.is_null() {
        return;
    }

    let mut session = Box::from_raw(session);
    let _ = stop_runtime(&mut session);
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_attach_surface(
    session: *mut BridgeSession,
    window_handle: usize,
    view_handle: usize,
    width: i32,
    height: i32,
    backing_scale_factor: f64,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if window_handle == 0 || view_handle == 0 || width <= 0 || height <= 0 || backing_scale_factor <= 0.0 {
        return session.set_error(
            "The Swift host provided an invalid embedded render surface descriptor.",
        );
    }

    session.surface = Some(HostSurfaceDescriptor {
        window_handle,
        view_handle,
        width,
        height,
        backing_scale_factor,
    });
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_update_surface(
    session: *mut BridgeSession,
    window_handle: usize,
    view_handle: usize,
    width: i32,
    height: i32,
    backing_scale_factor: f64,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if window_handle == 0 || view_handle == 0 || width <= 0 || height <= 0 || backing_scale_factor <= 0.0 {
        return session.set_error(
            "The Swift host provided an invalid embedded render surface descriptor.",
        );
    }

    session.surface = Some(HostSurfaceDescriptor {
        window_handle,
        view_handle,
        width,
        height,
        backing_scale_factor,
    });

    let pixel_width = ((width as f64) * backing_scale_factor).round() as i64;
    let pixel_height = ((height as f64) * backing_scale_factor).round() as i64;
    ui::video::set_host_viewport(pixel_width.max(1) as u32, pixel_height.max(1) as u32);

    if session.has_active_runtime() {
        if let Some(window) = session.sdl_window {
            if let Err(message) = ui::video::sync_embedded_window(window.as_ptr() as _) {
                return session.set_error(message);
            }
        }
    }

    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_open_rom(
    session: *mut BridgeSession,
    rom_path: *const c_char,
    config_dir: *const c_char,
    data_dir: *const c_char,
    cache_dir: *const c_char,
    molten_vk_library: *const c_char,
    fullscreen: i32,
    mute_audio: i32,
    speed_percent: i32,
    upscale_multiplier: i32,
    integer_scaling: i32,
    crt_filter: i32,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        if session.emulation_thread.is_some() {
            return Err("A ROM is already running inside the embedded gopher64 bridge.".to_string());
        }

        let surface = session
            .surface
            .clone()
            .ok_or_else(|| "A render surface must be attached before opening a ROM.".to_string())?;

        let rom_path = PathBuf::from(c_string_from_ptr(rom_path)?);
        let runtime_directories = RuntimeDirectories {
            config_dir: PathBuf::from(c_string_from_ptr(config_dir)?),
            data_dir: PathBuf::from(c_string_from_ptr(data_dir)?),
            cache_dir: PathBuf::from(c_string_from_ptr(cache_dir)?),
        };
        let molten_vk_library = if molten_vk_library.is_null() {
            None
        } else {
            let path = c_string_from_ptr(molten_vk_library)?;
            if path.is_empty() {
                None
            } else {
                Some(PathBuf::from(path))
            }
        };

        ensure_runtime_directories(&runtime_directories)?;
        let rom_contents = load_rom_contents(&rom_path)?;

        ui::video::ensure_video_subsystem_initialized();
        ui::video::load_vulkan_portability_library(molten_vk_library.as_deref())?;
        ui::video::set_host_viewport(surface.pixel_width(), surface.pixel_height());
        let embedded_window = ui::video::create_embedded_window(ui::video::EmbeddedWindowDescriptor {
            cocoa_window: surface.window_handle as *mut std::ffi::c_void,
            cocoa_view: surface.view_handle as *mut std::ffi::c_void,
            width: surface.width,
            height: surface.height,
            high_pixel_density: surface.backing_scale_factor > 1.0,
        })?;

        session.settings = RuntimeSettings {
            fullscreen: fullscreen != 0,
            mute_audio: mute_audio != 0,
            speed_percent: speed_percent.clamp(25, 300),
            upscale_multiplier: upscale_multiplier.clamp(1, 8),
            integer_scaling: integer_scaling != 0,
            crt_filter: crt_filter != 0,
            active_save_slot: 0,
        };
        session.current_rom_path = Some(rom_path);
        session.runtime_directories = Some(runtime_directories.clone());
        session.sdl_window = Some(EmbeddedWindowHandle(embedded_window as usize));
        session.renderer_name = CString::new("gopher64 + parallel-rdp (embedded)").unwrap();
        session.frame_rate = 0.0;
        session.pump_tick_count = 0;
        if let Ok(mut status) = session.runtime_status.lock() {
            status.active = false;
            status.running = false;
            status.paused = true;
            status.shutdown_requested = false;
            status.frame_rate = 0.0;
            status.last_error = None;
        }

        ui::input::reset_host_key_state();
        ui::video::set_hosted_mode(true);
        ui::video::set_initial_paused(true);

        let (startup_tx, startup_rx) = mpsc::channel();
        let runtime_status = Arc::clone(&session.runtime_status);
        session.emulation_thread = Some(spawn_runtime_thread(
            rom_contents,
            runtime_directories,
            session.settings.clone(),
            session.sdl_window.unwrap(),
            runtime_status,
            startup_tx,
        ));

        match startup_rx.recv_timeout(Duration::from_secs(15)) {
            Ok(Ok(frame_rate)) => {
                session.frame_rate = frame_rate;
                session.clear_error();
                Ok(())
            }
            Ok(Err(message)) => {
                let _ = stop_runtime(session);
                Err(message)
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                let _ = stop_runtime(session);
                Err("The embedded gopher64 runtime did not finish booting in time.".to_string())
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                let _ = stop_runtime(session);
                Err("The embedded gopher64 runtime stopped before it reported readiness.".to_string())
            }
        }
    }));

    match result {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => session.set_error(message),
        Err(_) => session.set_error(
            "The embedded gopher64 bridge panicked while preparing the emulation runtime.",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_pause(session: *mut BridgeSession) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    ui::video::set_paused(true);
    if let Ok(mut status) = session.runtime_status.lock() {
        status.running = false;
        status.paused = true;
    }
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_pump_events(session: *mut BridgeSession) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        return 0;
    }

    let result = catch_unwind(AssertUnwindSafe(|| {
        ui::video::pump_events_from_host();
    }));

    match result {
        Ok(()) => {
            session.update_error_from_runtime();
            let is_running = session
                .runtime_status
                .lock()
                .map(|status| status.running && !status.paused)
                .unwrap_or(false);
            if is_running {
                session.pump_tick_count = session.pump_tick_count.saturating_add(1);
            }
            0
        }
        Err(_) => session.set_error(
            "The embedded gopher64 bridge panicked while pumping SDL events on the host thread.",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_frame_count(session: *mut BridgeSession) -> u64 {
    match session_from_ptr(session) {
        Ok(session) => session.pump_tick_count,
        Err(_) => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_runtime_state(session: *mut BridgeSession) -> i32 {
    match session_from_ptr(session) {
        Ok(session) => session
            .runtime_status
            .lock()
            .map(|status| {
                if !status.active {
                    0
                } else if status.running && !status.paused {
                    2
                } else {
                    1
                }
            })
            .unwrap_or(0),
        Err(_) => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_resume(session: *mut BridgeSession) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    ui::video::set_paused(false);
    if let Ok(mut status) = session.runtime_status.lock() {
        status.running = true;
        status.paused = false;
    }
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_reset(session: *mut BridgeSession) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    ui::video::request_reset();
    session.settings.active_save_slot = 0;
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_save_state(session: *mut BridgeSession, slot: i32) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    let slot = slot.clamp(0, 9) as u32;
    session.settings.active_save_slot = slot as i32;
    ui::video::request_save_state(slot);
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_load_state(session: *mut BridgeSession, slot: i32) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    let slot = slot.clamp(0, 9) as u32;
    session.settings.active_save_slot = slot as i32;
    ui::video::request_load_state(slot);
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_update_settings(
    session: *mut BridgeSession,
    fullscreen: i32,
    mute_audio: i32,
    speed_percent: i32,
    upscale_multiplier: i32,
    integer_scaling: i32,
    crt_filter: i32,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    session.settings.fullscreen = fullscreen != 0;
    session.settings.mute_audio = mute_audio != 0;
    session.settings.speed_percent = speed_percent.clamp(25, 300);
    session.settings.upscale_multiplier = upscale_multiplier.clamp(1, 8);
    session.settings.integer_scaling = integer_scaling != 0;
    session.settings.crt_filter = crt_filter != 0;

    if session.has_active_runtime() {
        ui::video::set_fullscreen(session.settings.fullscreen);
    }

    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_set_keyboard_key(
    session: *mut BridgeSession,
    scancode: i32,
    pressed: i32,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if !session.has_active_runtime() {
        session.update_error_from_runtime();
        return session.set_error("No embedded gopher64 session is currently running.");
    }

    ui::input::set_host_key_state(scancode, pressed != 0);
    session.clear_error();
    0
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_stop(session: *mut BridgeSession) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    match stop_runtime(session) {
        Ok(()) => 0,
        Err(message) => session.set_error(message),
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_last_error(session: *mut BridgeSession) -> *const c_char {
    match session_from_ptr(session) {
        Ok(session) => {
            session.update_error_from_runtime();
            session.last_error.as_ptr()
        }
        Err(_) => b"The gopher64 bridge session handle was null.\0".as_ptr() as *const c_char,
    }
}

#[no_mangle]
pub extern "C" fn cinder64_bridge_version() -> *const c_char {
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_renderer_name(session: *mut BridgeSession) -> *const c_char {
    match session_from_ptr(session) {
        Ok(session) => session.renderer_name.as_ptr(),
        Err(_) => VERSION.as_ptr() as *const c_char,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_frame_rate(session: *mut BridgeSession) -> f64 {
    match session_from_ptr(session) {
        Ok(session) => session.frame_rate,
        Err(_) => 0.0,
    }
}
