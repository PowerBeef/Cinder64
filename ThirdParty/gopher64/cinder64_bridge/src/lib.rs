use gopher64::{device, ui};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

const VERSION: &[u8] = b"gopher64-cinder64-bridge 0.2.0\0";
const CINDER64_BRIDGE_ABI_VERSION: u32 = 1;
const SHUTDOWN_JOIN_TIMEOUT: Duration = Duration::from_secs(3);

const STATUS_OK: i32 = 0;
const STATUS_INVALID_ARGUMENT: i32 = 1;
#[allow(dead_code)]
const STATUS_INVALID_STATE: i32 = 2;
const STATUS_RUNTIME_ERROR: i32 = 3;
#[allow(dead_code)]
const STATUS_NOT_READY: i32 = 4;
#[allow(dead_code)]
const STATUS_TIMEOUT: i32 = 5;
#[allow(dead_code)]
const STATUS_PANIC: i32 = 6;
const STATUS_ABI_MISMATCH: i32 = 7;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Cinder64Error {
    code: u32,
    reserved: u32,
    message: *const c_char,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Cinder64Metrics {
    pump_tick_count: u64,
    vi_count: u64,
    render_frame_count: u64,
    present_count: u64,
    frame_rate_hz: f64,
    pending_command_count: u64,
    runtime_state: i32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Cinder64SurfaceDescriptor {
    surface_id: u64,
    generation: u64,
    window_handle: usize,
    view_handle: usize,
    logical_width: i32,
    logical_height: i32,
    pixel_width: i32,
    pixel_height: i32,
    backing_scale_factor: f64,
    revision: u64,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Cinder64Settings {
    fullscreen: i32,
    mute_audio: i32,
    speed_percent: i32,
    upscale_multiplier: i32,
    integer_scaling: i32,
    crt_filter: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Cinder64OpenRomRequest {
    rom_path: *const c_char,
    config_dir: *const c_char,
    data_dir: *const c_char,
    cache_dir: *const c_char,
    molten_vk_library: *const c_char,
    settings: Cinder64Settings,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Cinder64BridgeAPI {
    abi_version: u32,
    struct_size: u32,
    surface_descriptor_size: u32,
    settings_size: u32,
    open_rom_request_size: u32,
    metrics_size: u32,
    error_size: u32,
    reserved: u32,
    create_session: usize,
    destroy_session: usize,
    attach_surface: usize,
    update_surface: usize,
    open_rom: usize,
    pause: usize,
    resume: usize,
    reset: usize,
    save_state: usize,
    load_state: usize,
    update_settings: usize,
    set_keyboard_key: usize,
    stop: usize,
    pump_events: usize,
    get_last_error: usize,
    get_metrics: usize,
    version: usize,
    renderer_name: usize,
    surface_event: usize,
}

#[derive(Clone, Debug, PartialEq)]
struct HostSurfaceDescriptor {
    surface_id: u64,
    generation: u64,
    window_handle: usize,
    view_handle: usize,
    logical_width: i32,
    logical_height: i32,
    pixel_width: u32,
    pixel_height: u32,
    backing_scale_factor: f64,
    revision: u64,
}

impl HostSurfaceDescriptor {
    fn is_valid(&self) -> bool {
        self.surface_id != 0
            && self.generation != 0
            && self.window_handle != 0
            && self.view_handle != 0
            && self.logical_width > 0
            && self.logical_height > 0
            && self.pixel_width > 0
            && self.pixel_height > 0
            && self.backing_scale_factor > 0.0
            && self.revision > 0
    }

    fn matches_generation(&self, other: &HostSurfaceDescriptor) -> bool {
        self.surface_id == other.surface_id && self.generation == other.generation
    }

    fn matches_committed_geometry(&self, other: &HostSurfaceDescriptor) -> bool {
        self.matches_generation(other)
            && self.window_handle == other.window_handle
            && self.view_handle == other.view_handle
            && self.logical_width == other.logical_width
            && self.logical_height == other.logical_height
            && self.pixel_width == other.pixel_width
            && self.pixel_height == other.pixel_height
            && self.backing_scale_factor == other.backing_scale_factor
    }

    fn embedded_window_descriptor(&self) -> ui::video::EmbeddedWindowDescriptor {
        ui::video::EmbeddedWindowDescriptor {
            cocoa_window: self.window_handle as *mut std::ffi::c_void,
            cocoa_view: self.view_handle as *mut std::ffi::c_void,
            width: self.logical_width,
            height: self.logical_height,
            high_pixel_density: self.backing_scale_factor > 1.0,
        }
    }
}

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum SurfaceApplyAction {
    Attach,
    Resize,
    Reattach,
    NoOp,
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
    fn as_ptr<T>(self) -> *mut T {
        self.0 as *mut T
    }
}

#[cfg_attr(not(test), allow(dead_code))]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum SDLWindowOwnership {
    HostOwned,
    RuntimeOwned,
}

fn should_destroy_sdl_window_on_stop(ownership: SDLWindowOwnership) -> bool {
    matches!(ownership, SDLWindowOwnership::RuntimeOwned)
}

pub struct BridgeSession {
    surface: Option<HostSurfaceDescriptor>,
    last_applied_surface: Option<HostSurfaceDescriptor>,
    current_rom_path: Option<PathBuf>,
    runtime_directories: Option<RuntimeDirectories>,
    settings: RuntimeSettings,
    renderer_name: CString,
    last_error: CString,
    last_error_code: u32,
    last_surface_event: CString,
    frame_rate: f64,
    sdl_window: Option<EmbeddedWindowHandle>,
    sdl_window_ownership: SDLWindowOwnership,
    runtime_status: Arc<Mutex<RuntimeStatus>>,
    emulation_thread: Option<JoinHandle<()>>,
    pump_tick_count: u64,
    vi_count: u64,
    render_frame_count: u64,
    present_count: u64,
    pending_command_count: u64,
    last_metrics_sample_at: Option<Instant>,
    poisoned: bool,
}

impl BridgeSession {
    fn new() -> Self {
        Self {
            surface: None,
            last_applied_surface: None,
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
            last_error_code: STATUS_OK as u32,
            last_surface_event: CString::new("").unwrap(),
            frame_rate: 0.0,
            sdl_window: None,
            sdl_window_ownership: SDLWindowOwnership::HostOwned,
            runtime_status: Arc::new(Mutex::new(RuntimeStatus::default())),
            emulation_thread: None,
            pump_tick_count: 0,
            vi_count: 0,
            render_frame_count: 0,
            present_count: 0,
            pending_command_count: 0,
            last_metrics_sample_at: None,
            poisoned: false,
        }
    }

    fn set_error_with_status(&mut self, status: i32, message: impl AsRef<str>) -> i32 {
        self.last_error = sanitize_c_string(message.as_ref());
        self.last_error_code = status as u32;
        if let Ok(mut status) = self.runtime_status.lock() {
            status.last_error = Some(message.as_ref().to_string());
        }
        status
    }

    fn set_error(&mut self, message: impl AsRef<str>) -> i32 {
        self.set_error_with_status(STATUS_RUNTIME_ERROR, message)
    }

    fn clear_error(&mut self) {
        self.last_error = CString::new("").unwrap();
        self.last_error_code = STATUS_OK as u32;
        if let Ok(mut status) = self.runtime_status.lock() {
            status.last_error = None;
        }
    }

    fn set_surface_event(&mut self, message: impl AsRef<str>) {
        self.last_surface_event = sanitize_c_string(message.as_ref());
    }

    fn update_error_from_runtime(&mut self) {
        let runtime_error = self
            .runtime_status
            .lock()
            .ok()
            .and_then(|status| status.last_error.clone());
        if let Some(message) = runtime_error {
            self.last_error = sanitize_c_string(&message);
            self.last_error_code = STATUS_RUNTIME_ERROR as u32;
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

    fn mark_poisoned(&mut self, status_code: i32, message: impl AsRef<str>) {
        self.poisoned = true;
        self.last_error = sanitize_c_string(message.as_ref());
        self.last_error_code = status_code as u32;
        if let Ok(mut status) = self.runtime_status.lock() {
            status.active = false;
            status.running = false;
            status.paused = false;
            status.shutdown_requested = false;
            status.frame_rate = 0.0;
            status.last_error = Some(message.as_ref().to_string());
        }
    }

    fn ensure_not_poisoned(&self) -> Result<(), String> {
        if self.poisoned {
            Err(
                "The previous embedded gopher64 runtime shutdown did not complete cleanly; create a fresh bridge session before opening another ROM."
                    .to_string(),
            )
        } else {
            Ok(())
        }
    }

    fn metrics(&self) -> Cinder64Metrics {
        Cinder64Metrics {
            pump_tick_count: self.pump_tick_count,
            vi_count: self.vi_count,
            render_frame_count: self.render_frame_count,
            present_count: self.present_count,
            frame_rate_hz: self.frame_rate,
            pending_command_count: self.pending_command_count,
            runtime_state: self
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
            reserved: 0,
        }
    }
}

fn sanitize_c_string(message: &str) -> CString {
    CString::new(message.replace('\0', " ")).unwrap()
}

fn update_measured_frame_rate(
    session: &mut BridgeSession,
    now: Instant,
    counters: (u32, u32),
) -> Option<f64> {
    let Some(last_sample_at) = session.last_metrics_sample_at else {
        session.last_metrics_sample_at = Some(now);
        return None;
    };

    let elapsed = now.saturating_duration_since(last_sample_at);
    if elapsed < Duration::from_secs(1) {
        return None;
    }

    session.last_metrics_sample_at = Some(now);

    let (frames_rendered, vi_events) = counters;
    session.render_frame_count = session
        .render_frame_count
        .saturating_add(frames_rendered as u64);
    session.present_count = session.present_count.saturating_add(frames_rendered as u64);
    session.vi_count = session.vi_count.saturating_add(vi_events as u64);
    if vi_events == 0 {
        return None;
    }

    let measured = frames_rendered as f64 / elapsed.as_secs_f64();
    session.frame_rate = measured;
    if let Ok(mut status) = session.runtime_status.lock() {
        status.frame_rate = measured;
    }

    Some(measured)
}

unsafe fn session_from_ptr<'a>(session: *mut BridgeSession) -> Result<&'a mut BridgeSession, i32> {
    session.as_mut().ok_or(STATUS_INVALID_ARGUMENT)
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

impl From<Cinder64SurfaceDescriptor> for HostSurfaceDescriptor {
    fn from(value: Cinder64SurfaceDescriptor) -> Self {
        Self {
            surface_id: value.surface_id,
            generation: value.generation,
            window_handle: value.window_handle,
            view_handle: value.view_handle,
            logical_width: value.logical_width,
            logical_height: value.logical_height,
            pixel_width: value.pixel_width.max(1) as u32,
            pixel_height: value.pixel_height.max(1) as u32,
            backing_scale_factor: value.backing_scale_factor,
            revision: value.revision,
        }
    }
}

impl From<Cinder64Settings> for RuntimeSettings {
    fn from(value: Cinder64Settings) -> Self {
        Self {
            fullscreen: value.fullscreen != 0,
            mute_audio: value.mute_audio != 0,
            speed_percent: value.speed_percent.clamp(25, 300),
            upscale_multiplier: value.upscale_multiplier.clamp(1, 8),
            integer_scaling: value.integer_scaling != 0,
            crt_filter: value.crt_filter != 0,
            active_save_slot: 0,
        }
    }
}

unsafe fn copy_error_to_out(session: &mut BridgeSession, out_error: *mut Cinder64Error) -> i32 {
    let Some(out_error) = out_error.as_mut() else {
        return STATUS_INVALID_ARGUMENT;
    };
    session.update_error_from_runtime();
    *out_error = Cinder64Error {
        code: session.last_error_code,
        reserved: 0,
        message: session.last_error.as_ptr(),
    };
    STATUS_OK
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

fn determine_surface_apply_action(
    last_applied: Option<&HostSurfaceDescriptor>,
    incoming: &HostSurfaceDescriptor,
) -> SurfaceApplyAction {
    match last_applied {
        None => SurfaceApplyAction::Attach,
        Some(applied)
            if applied.revision == incoming.revision
                || applied.matches_committed_geometry(incoming) =>
        {
            SurfaceApplyAction::NoOp
        }
        Some(applied) if applied.matches_generation(incoming) => SurfaceApplyAction::Resize,
        Some(_) => SurfaceApplyAction::Reattach,
    }
}

fn surface_event_message(action: &str, surface: &HostSurfaceDescriptor, details: &str) -> String {
    format!(
        "render-surface action={action} surface_id={} generation={} revision={} logical={}x{} pixel={}x{} scale={:.2} {details}",
        surface.surface_id,
        surface.generation,
        surface.revision,
        surface.logical_width,
        surface.logical_height,
        surface.pixel_width,
        surface.pixel_height,
        surface.backing_scale_factor
    )
}

fn apply_surface_update(
    session: &mut BridgeSession,
    incoming: HostSurfaceDescriptor,
) -> Result<SurfaceApplyAction, String> {
    let action = determine_surface_apply_action(session.last_applied_surface.as_ref(), &incoming);

    match action {
        SurfaceApplyAction::NoOp => {
            session.set_surface_event(surface_event_message(
                "no-op",
                &incoming,
                "reason=unchanged-geometry",
            ));
        }
        SurfaceApplyAction::Attach => {
            ui::video::set_host_viewport(incoming.pixel_width, incoming.pixel_height);
            let window = session
                .sdl_window
                .ok_or_else(|| "The embedded SDL window has not been created yet.".to_string())?;
            ui::video::sync_embedded_window(window.as_ptr())?;
            session.set_surface_event(surface_event_message(
                "attach",
                &incoming,
                "viewport=ok sdl-sync=ok wsi-resize=ok",
            ));
        }
        SurfaceApplyAction::Resize => {
            ui::video::set_host_viewport(incoming.pixel_width, incoming.pixel_height);
            let window = session
                .sdl_window
                .ok_or_else(|| "The embedded SDL window has not been created yet.".to_string())?;
            ui::video::sync_embedded_window(window.as_ptr())?;
            session.set_surface_event(surface_event_message(
                "resize",
                &incoming,
                "viewport=ok sdl-sync=ok wsi-resize=ok",
            ));
        }
        SurfaceApplyAction::Reattach => {
            let current_window = session
                .sdl_window
                .ok_or_else(|| "The embedded SDL window has not been created yet.".to_string())?;
            let replacement_window =
                ui::video::create_embedded_window(incoming.embedded_window_descriptor())?;
            ui::video::replace_embedded_window(
                current_window.as_ptr(),
                replacement_window,
                incoming.pixel_width,
                incoming.pixel_height,
            )?;
            if should_destroy_sdl_window_on_stop(session.sdl_window_ownership) {
                ui::video::destroy_embedded_window(current_window.as_ptr());
            }
            session.sdl_window = Some(EmbeddedWindowHandle(replacement_window as usize));
            session.sdl_window_ownership = SDLWindowOwnership::HostOwned;
            session.set_surface_event(surface_event_message(
                "reattach",
                &incoming,
                "replacement-window=create-ok wsi-rebind=ok",
            ));
        }
    }

    session.surface = Some(incoming.clone());
    session.last_applied_surface = Some(incoming);
    Ok(action)
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
            device.ui.video.window = embedded_window.as_ptr();
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
            device::run_game_with_ready_hook(&mut device, &rom_contents, game_settings, |device| {
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
            });

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
                status.last_error = Some(
                    "The embedded gopher64 runtime exited unexpectedly after boot.".to_string(),
                );
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

#[derive(Debug, PartialEq, Eq)]
enum JoinOutcome {
    Completed,
    Panicked,
    TimedOut,
}

fn join_with_timeout(thread: JoinHandle<()>, timeout: Duration) -> JoinOutcome {
    let (tx, rx) = mpsc::sync_channel::<std::thread::Result<()>>(1);
    std::thread::spawn(move || {
        let _ = tx.send(thread.join());
    });

    match rx.recv_timeout(timeout) {
        Ok(Ok(())) => JoinOutcome::Completed,
        Ok(Err(_)) => JoinOutcome::Panicked,
        Err(mpsc::RecvTimeoutError::Timeout) | Err(mpsc::RecvTimeoutError::Disconnected) => {
            JoinOutcome::TimedOut
        }
    }
}

fn stop_runtime(session: &mut BridgeSession) -> Result<(), String> {
    ui::input::reset_host_key_state();
    let should_destroy_window = should_destroy_sdl_window_on_stop(session.sdl_window_ownership);

    if session.emulation_thread.is_none() {
        ui::video::set_hosted_mode(false);
        ui::video::reset_runtime_counters();
        if should_destroy_window {
            if let Some(window) = session.sdl_window.take() {
                ui::video::destroy_embedded_window(window.as_ptr());
            }
        }
        session.last_applied_surface = None;
        session.current_rom_path = None;
        session.frame_rate = 0.0;
        session.pump_tick_count = 0;
        session.vi_count = 0;
        session.render_frame_count = 0;
        session.present_count = 0;
        session.pending_command_count = 0;
        session.last_metrics_sample_at = None;
        return Ok(());
    }

    if let Ok(mut status) = session.runtime_status.lock() {
        status.shutdown_requested = true;
    }
    ui::video::request_shutdown();

    let mut shutdown_timed_out = false;
    let mut panic_error: Option<String> = None;

    if let Some(thread) = session.emulation_thread.take() {
        match join_with_timeout(thread, SHUTDOWN_JOIN_TIMEOUT) {
            JoinOutcome::Completed => {
                ui::video::set_hosted_mode(false);
                ui::video::reset_runtime_counters();
            }
            JoinOutcome::Panicked => {
                ui::video::set_hosted_mode(false);
                ui::video::reset_runtime_counters();
                panic_error =
                    Some("The embedded gopher64 runtime panicked while shutting down.".to_string());
            }
            JoinOutcome::TimedOut => {
                // The emulation thread is wedged (commonly on a blocking Vulkan
                // present under MoltenVK). The JoinHandle and joiner helper are
                // leaked rather than stalling the host. Keep hosted mode active:
                // the abandoned thread may still be inside the hosted callback
                // boundary, and flipping it here can send SDL work down the wrong
                // side of the bridge while teardown is already underway.
                shutdown_timed_out = true;
            }
        }
    }

    let shutdown_error = if shutdown_timed_out {
        session
            .runtime_status
            .try_lock()
            .ok()
            .and_then(|status| status.last_error.clone())
    } else {
        session
            .runtime_status
            .lock()
            .ok()
            .and_then(|status| status.last_error.clone())
    };

    if should_destroy_window && !shutdown_timed_out {
        if let Some(window) = session.sdl_window.take() {
            ui::video::destroy_embedded_window(window.as_ptr());
        }
    }
    session.last_applied_surface = None;
    session.current_rom_path = None;
    session.frame_rate = 0.0;
    session.pump_tick_count = 0;
    session.vi_count = 0;
    session.render_frame_count = 0;
    session.present_count = 0;
    session.pending_command_count = 0;
    session.last_metrics_sample_at = None;
    if shutdown_timed_out {
        if let Ok(mut status) = session.runtime_status.try_lock() {
            status.active = false;
            status.running = false;
            status.paused = false;
            status.shutdown_requested = false;
            status.frame_rate = 0.0;
        }
    } else if let Ok(mut status) = session.runtime_status.lock() {
        status.active = false;
        status.running = false;
        status.paused = false;
        status.shutdown_requested = false;
        status.frame_rate = 0.0;
    }

    if let Some(message) = panic_error {
        session.mark_poisoned(STATUS_PANIC, &message);
        return Err(message);
    }
    if shutdown_timed_out {
        let message = format!(
            "The embedded gopher64 runtime did not shut down within {} seconds; the runtime thread was abandoned so the host process can exit.",
            SHUTDOWN_JOIN_TIMEOUT.as_secs()
        );
        session.mark_poisoned(STATUS_TIMEOUT, &message);
        return Err(message);
    }
    if let Some(message) = shutdown_error {
        return Err(message);
    }

    session.clear_error();
    session.poisoned = false;
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
    logical_width: i32,
    logical_height: i32,
    pixel_width: i32,
    pixel_height: i32,
    backing_scale_factor: f64,
    revision: u64,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if let Err(message) = session.ensure_not_poisoned() {
        return session.set_error_with_status(STATUS_INVALID_STATE, message);
    }

    let surface = HostSurfaceDescriptor {
        surface_id: 1,
        generation: 1,
        window_handle,
        view_handle,
        logical_width,
        logical_height,
        pixel_width: pixel_width.max(1) as u32,
        pixel_height: pixel_height.max(1) as u32,
        backing_scale_factor,
        revision,
    };

    if !surface.is_valid() {
        return session
            .set_error("The Swift host provided an invalid embedded render surface descriptor.");
    }

    if session.has_active_runtime() {
        match apply_surface_update(session, surface) {
            Ok(_) => {
                session.clear_error();
                0
            }
            Err(message) => session.set_error(message),
        }
    } else {
        session.set_surface_event(surface_event_message(
            "pending",
            &surface,
            "reason=runtime-inactive",
        ));
        session.surface = Some(surface);
        session.clear_error();
        0
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_update_surface(
    session: *mut BridgeSession,
    window_handle: usize,
    view_handle: usize,
    logical_width: i32,
    logical_height: i32,
    pixel_width: i32,
    pixel_height: i32,
    backing_scale_factor: f64,
    revision: u64,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return -1;
    };

    if let Err(message) = session.ensure_not_poisoned() {
        return session.set_error_with_status(STATUS_INVALID_STATE, message);
    }

    let surface = HostSurfaceDescriptor {
        surface_id: 1,
        generation: 1,
        window_handle,
        view_handle,
        logical_width,
        logical_height,
        pixel_width: pixel_width.max(1) as u32,
        pixel_height: pixel_height.max(1) as u32,
        backing_scale_factor,
        revision,
    };

    if !surface.is_valid() {
        return session
            .set_error("The Swift host provided an invalid embedded render surface descriptor.");
    }

    if !session.has_active_runtime() {
        session.set_surface_event(surface_event_message(
            "pending",
            &surface,
            "reason=runtime-inactive",
        ));
        session.surface = Some(surface);
        session.clear_error();
        return 0;
    }

    match apply_surface_update(session, surface) {
        Ok(_) => {
            session.clear_error();
            0
        }
        Err(message) => session.set_error(message),
    }
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
    if let Err(message) = session.ensure_not_poisoned() {
        return session.set_error_with_status(STATUS_INVALID_STATE, message);
    }

    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        if session.emulation_thread.is_some() {
            return Err(
                "A ROM is already running inside the embedded gopher64 bridge.".to_string(),
            );
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
        ui::video::set_host_viewport(surface.pixel_width, surface.pixel_height);
        let (embedded_window, window_creation_details) =
            if let Some(existing_window) = session.sdl_window {
                ui::video::sync_embedded_window(existing_window.as_ptr())?;
                (
                    existing_window,
                    "viewport=ok sdl-window=reuse-ok wsi=initial-bind",
                )
            } else {
                let embedded_window =
                    ui::video::create_embedded_window(surface.embedded_window_descriptor())?;
                let embedded_window = EmbeddedWindowHandle(embedded_window as usize);
                session.sdl_window = Some(embedded_window);
                session.sdl_window_ownership = SDLWindowOwnership::HostOwned;
                (
                    embedded_window,
                    "viewport=ok sdl-window=create-ok wsi=initial-bind",
                )
            };

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
        session.sdl_window = Some(embedded_window);
        session.last_applied_surface = Some(surface.clone());
        session.set_surface_event(surface_event_message(
            "attach",
            &surface,
            window_creation_details,
        ));
        session.renderer_name = CString::new("gopher64 + parallel-rdp (embedded)").unwrap();
        session.frame_rate = 0.0;
        session.pump_tick_count = 0;
        session.vi_count = 0;
        session.render_frame_count = 0;
        session.present_count = 0;
        session.pending_command_count = 0;
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
        ui::video::reset_runtime_counters();
        ui::video::set_initial_paused(true);

        let (startup_tx, startup_rx) = mpsc::channel();
        let runtime_status = Arc::clone(&session.runtime_status);
        session.emulation_thread = Some(spawn_runtime_thread(
            rom_contents,
            runtime_directories,
            session.settings.clone(),
            embedded_window,
            runtime_status,
            startup_tx,
        ));

        match startup_rx.recv_timeout(Duration::from_secs(15)) {
            Ok(Ok(frame_rate)) => {
                session.frame_rate = frame_rate;
                session.last_metrics_sample_at = Some(Instant::now());
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
                Err(
                    "The embedded gopher64 runtime stopped before it reported readiness."
                        .to_string(),
                )
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
                let now = Instant::now();
                let sample_due = session
                    .last_metrics_sample_at
                    .map(|last_sample_at| {
                        now.saturating_duration_since(last_sample_at) >= Duration::from_secs(1)
                    })
                    .unwrap_or(true);
                if sample_due {
                    let counters = ui::video::take_runtime_counters();
                    let _ = update_measured_frame_rate(session, now, counters);
                }
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
    ui::video::reset_runtime_counters();
    session.last_metrics_sample_at = Some(Instant::now());
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
        Err(message) => {
            let status = if session.poisoned {
                session.last_error_code as i32
            } else {
                STATUS_RUNTIME_ERROR
            };
            session.set_error_with_status(status, message)
        }
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
pub unsafe extern "C" fn cinder64_bridge_surface_event(
    session: *mut BridgeSession,
) -> *const c_char {
    match session_from_ptr(session) {
        Ok(session) => session.last_surface_event.as_ptr(),
        Err(_) => b"\0".as_ptr() as *const c_char,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_attach_surface_v1(
    session: *mut BridgeSession,
    descriptor: *const Cinder64SurfaceDescriptor,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return STATUS_INVALID_ARGUMENT;
    };
    if let Err(message) = session.ensure_not_poisoned() {
        return session.set_error_with_status(STATUS_INVALID_STATE, message);
    }
    let Some(descriptor) = descriptor.as_ref() else {
        return session.set_error_with_status(
            STATUS_INVALID_ARGUMENT,
            "The Swift host provided a null render surface descriptor.",
        );
    };

    let surface = HostSurfaceDescriptor::from(*descriptor);
    if !surface.is_valid() {
        return session.set_error_with_status(
            STATUS_INVALID_ARGUMENT,
            "The Swift host provided an invalid embedded render surface descriptor.",
        );
    }

    if session.has_active_runtime() {
        match apply_surface_update(session, surface) {
            Ok(_) => {
                session.clear_error();
                STATUS_OK
            }
            Err(message) => session.set_error_with_status(STATUS_RUNTIME_ERROR, message),
        }
    } else {
        session.set_surface_event(surface_event_message(
            "pending",
            &surface,
            "reason=runtime-inactive",
        ));
        session.surface = Some(surface);
        session.clear_error();
        STATUS_OK
    }
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_update_surface_v1(
    session: *mut BridgeSession,
    descriptor: *const Cinder64SurfaceDescriptor,
) -> i32 {
    cinder64_bridge_attach_surface_v1(session, descriptor)
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_open_rom_v1(
    session: *mut BridgeSession,
    request: *const Cinder64OpenRomRequest,
) -> i32 {
    let Some(request) = request.as_ref() else {
        return STATUS_INVALID_ARGUMENT;
    };

    cinder64_bridge_open_rom(
        session,
        request.rom_path,
        request.config_dir,
        request.data_dir,
        request.cache_dir,
        request.molten_vk_library,
        request.settings.fullscreen,
        request.settings.mute_audio,
        request.settings.speed_percent,
        request.settings.upscale_multiplier,
        request.settings.integer_scaling,
        request.settings.crt_filter,
    )
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_update_settings_v1(
    session: *mut BridgeSession,
    settings: *const Cinder64Settings,
) -> i32 {
    let Some(settings) = settings.as_ref() else {
        return STATUS_INVALID_ARGUMENT;
    };

    cinder64_bridge_update_settings(
        session,
        settings.fullscreen,
        settings.mute_audio,
        settings.speed_percent,
        settings.upscale_multiplier,
        settings.integer_scaling,
        settings.crt_filter,
    )
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_get_last_error_v1(
    session: *mut BridgeSession,
    out_error: *mut Cinder64Error,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return STATUS_INVALID_ARGUMENT;
    };
    copy_error_to_out(session, out_error)
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_get_metrics_v1(
    session: *mut BridgeSession,
    out_metrics: *mut Cinder64Metrics,
) -> i32 {
    let Ok(session) = session_from_ptr(session) else {
        return STATUS_INVALID_ARGUMENT;
    };
    let Some(out_metrics) = out_metrics.as_mut() else {
        return STATUS_INVALID_ARGUMENT;
    };
    *out_metrics = session.metrics();
    STATUS_OK
}

#[cfg(test)]
mod surface_state_tests;

#[no_mangle]
pub extern "C" fn cinder64_bridge_version() -> *const c_char {
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_renderer_name(
    session: *mut BridgeSession,
) -> *const c_char {
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

#[no_mangle]
pub unsafe extern "C" fn cinder64_bridge_get_api(
    requested_abi_version: u32,
    api_struct_size: u32,
    out_api: *mut Cinder64BridgeAPI,
) -> i32 {
    if requested_abi_version != CINDER64_BRIDGE_ABI_VERSION {
        return STATUS_ABI_MISMATCH;
    }

    let Some(out_api) = out_api.as_mut() else {
        return STATUS_INVALID_ARGUMENT;
    };

    if api_struct_size != std::mem::size_of::<Cinder64BridgeAPI>() as u32 {
        return STATUS_ABI_MISMATCH;
    }

    *out_api = Cinder64BridgeAPI {
        abi_version: CINDER64_BRIDGE_ABI_VERSION,
        struct_size: std::mem::size_of::<Cinder64BridgeAPI>() as u32,
        surface_descriptor_size: std::mem::size_of::<Cinder64SurfaceDescriptor>() as u32,
        settings_size: std::mem::size_of::<Cinder64Settings>() as u32,
        open_rom_request_size: std::mem::size_of::<Cinder64OpenRomRequest>() as u32,
        metrics_size: std::mem::size_of::<Cinder64Metrics>() as u32,
        error_size: std::mem::size_of::<Cinder64Error>() as u32,
        reserved: 0,
        create_session: cinder64_bridge_create_session as *const () as usize,
        destroy_session: cinder64_bridge_destroy_session as *const () as usize,
        attach_surface: cinder64_bridge_attach_surface_v1 as *const () as usize,
        update_surface: cinder64_bridge_update_surface_v1 as *const () as usize,
        open_rom: cinder64_bridge_open_rom_v1 as *const () as usize,
        pause: cinder64_bridge_pause as *const () as usize,
        resume: cinder64_bridge_resume as *const () as usize,
        reset: cinder64_bridge_reset as *const () as usize,
        save_state: cinder64_bridge_save_state as *const () as usize,
        load_state: cinder64_bridge_load_state as *const () as usize,
        update_settings: cinder64_bridge_update_settings_v1 as *const () as usize,
        set_keyboard_key: cinder64_bridge_set_keyboard_key as *const () as usize,
        stop: cinder64_bridge_stop as *const () as usize,
        pump_events: cinder64_bridge_pump_events as *const () as usize,
        get_last_error: cinder64_bridge_get_last_error_v1 as *const () as usize,
        get_metrics: cinder64_bridge_get_metrics_v1 as *const () as usize,
        version: cinder64_bridge_version as *const () as usize,
        renderer_name: cinder64_bridge_renderer_name as *const () as usize,
        surface_event: cinder64_bridge_surface_event as *const () as usize,
    };

    STATUS_OK
}
