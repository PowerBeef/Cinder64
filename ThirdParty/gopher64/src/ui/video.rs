#![allow(non_snake_case)]
include!(concat!(env!("OUT_DIR"), "/parallel_bindings.rs"));
use crate::{device, retroachievements, ui};
use std::ffi::CStr;
use std::ffi::c_void;
use std::ffi::CString;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

const PAL_WIDESCREEN_WIDTH: i32 = 512;
const PAL_STANDARD_WIDTH: i32 = 384;
const PAL_HEIGHT: i32 = 288;
const NTSC_WIDESCREEN_WIDTH: i32 = 426;
const NTSC_STANDARD_WIDTH: i32 = 320;
const NTSC_HEIGHT: i32 = 240;

unsafe extern "C" {
    fn rdp_is_ready() -> bool;
    fn rdp_set_initial_paused(paused: bool);
    fn rdp_set_paused(paused: bool);
    fn rdp_request_save_state(slot: u32);
    fn rdp_request_load_state(slot: u32);
    fn rdp_request_reset();
    fn rdp_request_shutdown();
    fn rdp_set_fullscreen(fullscreen: bool);
    fn rdp_set_host_viewport(width: u32, height: u32);
    fn rdp_rebind_window(window: *mut c_void, width: u32, height: u32) -> bool;
    fn rdp_last_close_error() -> *const std::ffi::c_char;
}

static HOSTED_RUNTIME_ACTIVE: AtomicBool = AtomicBool::new(false);
static RUNTIME_FRAME_EVENTS: AtomicU32 = AtomicU32::new(0);
static RUNTIME_VI_EVENTS: AtomicU32 = AtomicU32::new(0);

pub struct EmbeddedWindowDescriptor {
    pub cocoa_window: *mut c_void,
    pub cocoa_view: *mut c_void,
    pub width: i32,
    pub height: i32,
    pub high_pixel_density: bool,
}

fn sdl_error(prefix: &str) -> String {
    format!(
        "{prefix}: {}",
        unsafe {
            std::ffi::CStr::from_ptr(sdl3_sys::error::SDL_GetError())
                .to_str()
                .unwrap_or("Unknown SDL error")
        }
    )
}

pub fn create_embedded_window(
    descriptor: EmbeddedWindowDescriptor,
) -> Result<*mut sdl3_sys::video::SDL_Window, String> {
    if descriptor.cocoa_window.is_null() || descriptor.cocoa_view.is_null() {
        return Err("Cinder64 must provide both an NSWindow and NSView for embedded rendering."
            .to_string());
    }

    unsafe {
        if sdl3_sys::init::SDL_WasInit(sdl3_sys::init::SDL_INIT_VIDEO) == 0
            && !sdl3_sys::init::SDL_InitSubSystem(sdl3_sys::init::SDL_INIT_VIDEO)
        {
            return Err(sdl_error("Could not initialize SDL video"));
        }
    }

    let props = unsafe { sdl3_sys::properties::SDL_CreateProperties() };
    if props == 0 {
        return Err(sdl_error("Could not allocate SDL window properties"));
    }

    let result = (|| {
        unsafe {
            if !sdl3_sys::properties::SDL_SetPointerProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_COCOA_WINDOW_POINTER,
                descriptor.cocoa_window,
            ) {
                return Err(sdl_error("Could not attach the host NSWindow"));
            }

            if !sdl3_sys::properties::SDL_SetPointerProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_COCOA_VIEW_POINTER,
                descriptor.cocoa_view,
            ) {
                return Err(sdl_error("Could not attach the host NSView"));
            }

            if !sdl3_sys::properties::SDL_SetBooleanProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_VULKAN_BOOLEAN,
                true,
            ) {
                return Err(sdl_error("Could not mark the embedded window as Vulkan-capable"));
            }

            if !sdl3_sys::properties::SDL_SetBooleanProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN,
                true,
            ) {
                return Err(sdl_error("Could not mark the embedded window as resizable"));
            }

            if !sdl3_sys::properties::SDL_SetBooleanProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN,
                descriptor.high_pixel_density,
            ) {
                return Err(sdl_error("Could not enable high pixel density on the embedded window"));
            }

            if !sdl3_sys::properties::SDL_SetNumberProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER,
                descriptor.width as i64,
            ) || !sdl3_sys::properties::SDL_SetNumberProperty(
                props,
                sdl3_sys::video::SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER,
                descriptor.height as i64,
            ) {
                return Err(sdl_error("Could not set the embedded window size"));
            }

            let window = sdl3_sys::video::SDL_CreateWindowWithProperties(props);
            if window.is_null() {
                return Err(sdl_error("Could not wrap the host render surface in SDL"));
            }

            if !sdl3_sys::video::SDL_SyncWindow(window) {
                let message = sdl_error("Could not synchronize the embedded SDL window");
                sdl3_sys::video::SDL_DestroyWindow(window);
                return Err(message);
            }

            Ok(window)
        }
    })();

    unsafe {
        sdl3_sys::properties::SDL_DestroyProperties(props);
    }

    result
}

pub fn ensure_video_subsystem_initialized() {
    ui::sdl_init(sdl3_sys::init::SDL_INIT_VIDEO);
}

pub fn load_vulkan_portability_library(path: Option<&Path>) -> Result<(), String> {
    let owned_path = path
        .map(|path| {
            CString::new(path.as_os_str().as_bytes())
                .map_err(|_| "The MoltenVK path contains an interior null byte.".to_string())
        })
        .transpose()?;
    let raw_path = owned_path
        .as_ref()
        .map_or(std::ptr::null(), |path| path.as_ptr());

    unsafe {
        if !sdl3_sys::vulkan::SDL_Vulkan_LoadLibrary(raw_path) {
            return Err(sdl_error("Could not load the Vulkan portability library"));
        }
    }

    Ok(())
}

pub fn set_hosted_mode(hosted: bool) {
    HOSTED_RUNTIME_ACTIVE.store(hosted, Ordering::SeqCst);
}

pub fn reset_runtime_counters() {
    RUNTIME_FRAME_EVENTS.store(0, Ordering::SeqCst);
    RUNTIME_VI_EVENTS.store(0, Ordering::SeqCst);
}

pub fn record_presented_frame() {
    if HOSTED_RUNTIME_ACTIVE.load(Ordering::SeqCst) {
        RUNTIME_FRAME_EVENTS.fetch_add(1, Ordering::SeqCst);
    }
}

pub fn record_vi_event() {
    if HOSTED_RUNTIME_ACTIVE.load(Ordering::SeqCst) {
        RUNTIME_VI_EVENTS.fetch_add(1, Ordering::SeqCst);
    }
}

pub fn take_runtime_counters() -> (u32, u32) {
    (
        RUNTIME_FRAME_EVENTS.swap(0, Ordering::SeqCst),
        RUNTIME_VI_EVENTS.swap(0, Ordering::SeqCst),
    )
}

pub fn set_host_viewport(width: u32, height: u32) {
    unsafe {
        rdp_set_host_viewport(width.max(1), height.max(1));
    }
}

pub fn pump_events_from_runtime() {
    if !HOSTED_RUNTIME_ACTIVE.load(Ordering::SeqCst) {
        unsafe { sdl3_sys::events::SDL_PumpEvents() };
    }
}

pub fn pump_events_from_host() {
    unsafe { sdl3_sys::events::SDL_PumpEvents() };
}

pub fn destroy_embedded_window(window: *mut sdl3_sys::video::SDL_Window) {
    if window.is_null() {
        return;
    }

    unsafe {
        sdl3_sys::video::SDL_DestroyWindow(window);
    }
}

pub fn replace_embedded_window(
    _current_window: *mut sdl3_sys::video::SDL_Window,
    replacement_window: *mut sdl3_sys::video::SDL_Window,
    width: u32,
    height: u32,
) -> Result<(), String> {
    if replacement_window.is_null() {
        return Err("The replacement embedded SDL window has not been created yet.".to_string());
    }

    if unsafe { rdp_rebind_window(replacement_window as *mut c_void, width, height) } {
        Ok(())
    } else {
        Err("Could not rebind the embedded SDL window to the hosted renderer.".to_string())
    }
}

fn build_gfx_info(device: &mut device::Device) -> GFX_INFO {
    GFX_INFO {
        RDRAM: device.rdram.mem.as_mut_ptr(),
        DMEM: device.rsp.mem.as_mut_ptr(),
        RDRAM_SIZE: device.rdram.size,
        DPC_CURRENT_REG: &mut device.rdp.regs_dpc[device::rdp::DPC_CURRENT_REG as usize],
        DPC_START_REG: &mut device.rdp.regs_dpc[device::rdp::DPC_START_REG as usize],
        DPC_END_REG: &mut device.rdp.regs_dpc[device::rdp::DPC_END_REG as usize],
        DPC_STATUS_REG: &mut device.rdp.regs_dpc[device::rdp::DPC_STATUS_REG as usize],
        PAL: device.cart.pal,
        widescreen: device.ui.config.video.widescreen,
        fullscreen: device.ui.video.fullscreen,
        vsync: true,
        integer_scaling: device.ui.config.video.integer_scaling,
        upscale: device.ui.config.video.upscale,
        crt: device.ui.config.video.crt,
    }
}

pub fn init(device: &mut device::Device) {
    ui::sdl_init(sdl3_sys::init::SDL_INIT_VIDEO);
    ui::ttf_init();
    reset_runtime_counters();

    let embedded_window = !device.ui.video.window.is_null();
    device.ui.video.host_owned_window =
        embedded_window && HOSTED_RUNTIME_ACTIVE.load(Ordering::SeqCst);
    if embedded_window {
    } else {
        let window_title = std::ffi::CString::new("gopher64").unwrap();

        let mut flags = sdl3_sys::video::SDL_WINDOW_VULKAN
            | sdl3_sys::video::SDL_WINDOW_RESIZABLE
            | sdl3_sys::video::SDL_WINDOW_INPUT_FOCUS;

        if device.ui.video.fullscreen {
            flags |= sdl3_sys::video::SDL_WINDOW_FULLSCREEN;
        }

        let window_width;
        let window_height;
        let scale = if device.ui.config.video.upscale > 1 {
            device.ui.config.video.upscale as i32
        } else {
            2
        };
        if device.cart.pal {
            window_width = if device.ui.config.video.widescreen {
                PAL_WIDESCREEN_WIDTH * scale
            } else {
                PAL_STANDARD_WIDTH * scale
            };
            window_height = PAL_HEIGHT * scale;
        } else {
            window_width = if device.ui.config.video.widescreen {
                NTSC_WIDESCREEN_WIDTH * scale
            } else {
                NTSC_STANDARD_WIDTH * scale
            };
            window_height = NTSC_HEIGHT * scale;
        }
        device.ui.video.window = unsafe {
            sdl3_sys::video::SDL_CreateWindow(
                window_title.as_ptr(),
                window_width,
                window_height,
                flags,
            )
        };
        if device.ui.video.window.is_null() {
            panic!("{}", sdl_error("Could not create an SDL window"));
        }
        if !unsafe { sdl3_sys::video::SDL_ShowWindow(device.ui.video.window) } {
            panic!("{}", sdl_error("Could not show the SDL window"));
        }
    }
    unsafe {
        sdl3_sys::everything::SDL_HideCursor();
        let hint = std::ffi::CString::new("1").unwrap();
        sdl3_sys::everything::SDL_SetHint(
            sdl3_sys::everything::SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,
            hint.as_ptr(),
        );
    }

    let gfx_info = build_gfx_info(device);

    unsafe {
        let font_bytes = include_bytes!("../../data/RobotoMono-Regular.ttf");
        rdp_init(
            device.ui.video.window as *mut std::ffi::c_void,
            gfx_info,
            font_bytes.as_ptr() as *const std::ffi::c_void,
            font_bytes.len(),
            device.ui.storage.save_state_slot,
        )
    };

    if !unsafe { rdp_is_ready() } {
        panic!("parallel-rdp did not finish initializing");
    }
}

pub fn close(ui: &ui::Ui) {
    unsafe {
        rdp_close();
        if !ui.video.host_owned_window {
            sdl3_sys::video::SDL_DestroyWindow(ui.video.window);
        }
    }
    reset_runtime_counters();
}

pub fn last_close_error() -> Option<String> {
    let raw = unsafe { rdp_last_close_error() };
    if raw.is_null() {
        return None;
    }

    Some(unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned())
}

pub fn update_screen() {
    unsafe { rdp_update_screen() }
}

pub fn render_frame() {
    unsafe { rdp_render_frame() }
}

pub fn state_size() -> usize {
    unsafe { rdp_state_size() }
}

pub fn save_state(rdp_state: *mut u8) {
    unsafe { rdp_save_state(rdp_state) }
}

pub fn load_state(device: &mut device::Device, rdp_state: *const u8) {
    let gfx_info = build_gfx_info(device);
    unsafe {
        rdp_new_processor(gfx_info);
        rdp_load_state(rdp_state);
        for reg in 0..device::vi::VI_REGS_COUNT {
            rdp_set_vi_register(reg, device.vi.regs[reg as usize])
        }
    }
}

pub fn pause_loop(frame_time: f64) {
    let mut paused = true;
    let mut frame_advance = false;
    while paused && !frame_advance {
        std::thread::sleep(std::time::Duration::from_secs_f64(frame_time));
        pump_events_from_runtime();
        retroachievements::do_idle();
        let callback = unsafe { rdp_check_callback() };
        paused = callback.paused;
        frame_advance = callback.frame_advance;
    }
}

pub fn check_callback(device: &mut device::Device) -> (bool, bool) {
    let mut speed_limiter_toggled = false;
    let callback = unsafe { rdp_check_callback() };
    device.cpu.running = callback.emu_running;
    if device.netplay.is_none() {
        if callback.save_state {
            device.save_state = true;
        } else if callback.load_state {
            device.load_state = true;
        }
        if callback.reset_game {
            device.cpu.cop0.regs[device::cop0::COP0_CAUSE_REG as usize] |=
                device::cop0::COP0_CAUSE_IP4;
            device.cpu.cop0.regs[device::cop0::COP0_CAUSE_REG as usize] &=
                !device::cop0::COP0_CAUSE_EXCCODE_MASK;

            device::events::create_event(
                device,
                device::events::EVENT_TYPE_NMI,
                device.cpu.clock_rate, // 1 second
            );
        }
        if device.vi.enable_speed_limiter != callback.enable_speedlimiter {
            speed_limiter_toggled = true;
            device.vi.enable_speed_limiter = callback.enable_speedlimiter;
        }
    }

    if device.ui.storage.save_state_slot != callback.save_state_slot {
        onscreen_message(
            &format!("Switching savestate slot to {}", callback.save_state_slot),
            false,
        );
        device.ui.storage.save_state_slot = callback.save_state_slot;
        device
            .ui
            .storage
            .paths
            .savestate_file_path
            .set_extension(format!("state{}", callback.save_state_slot));
    }
    if callback.lower_volume {
        ui::audio::lower_audio_volume(&mut device.ui);
    } else if callback.raise_volume {
        ui::audio::raise_audio_volume(&mut device.ui);
    }
    (speed_limiter_toggled, callback.paused)
}

pub fn set_register(reg: u32, value: u32) {
    unsafe {
        rdp_set_vi_register(reg, value);
    }
}

pub fn process_rdp_list() -> u64 {
    unsafe { rdp_process_commands() }
}

pub fn check_framebuffers(address: u32, length: u32) {
    unsafe { rdp_check_framebuffers(address, length) }
}

pub fn onscreen_message(message: &str, long_message: bool) {
    unsafe {
        let c_message = std::ffi::CString::new(message).unwrap();
        rdp_onscreen_message(c_message.as_ptr(), long_message)
    };
}

pub fn set_initial_paused(paused: bool) {
    unsafe { rdp_set_initial_paused(paused) }
}

pub fn set_paused(paused: bool) {
    unsafe { rdp_set_paused(paused) }
}

pub fn request_save_state(slot: u32) {
    unsafe { rdp_request_save_state(slot) }
}

pub fn request_load_state(slot: u32) {
    unsafe { rdp_request_load_state(slot) }
}

pub fn request_reset() {
    unsafe { rdp_request_reset() }
}

pub fn request_shutdown() {
    unsafe { rdp_request_shutdown() }
}

pub fn set_fullscreen(fullscreen: bool) {
    unsafe { rdp_set_fullscreen(fullscreen) }
}

pub fn sync_embedded_window(window: *mut sdl3_sys::video::SDL_Window) -> Result<(), String> {
    if window.is_null() {
        return Err("The embedded SDL window has not been created yet.".to_string());
    }

    if unsafe { sdl3_sys::video::SDL_SyncWindow(window) } {
        Ok(())
    } else {
        Err(sdl_error("Could not synchronize the embedded SDL window"))
    }
}

pub fn draw_text(
    text: &str,
    renderer: *mut sdl3_sys::render::SDL_Renderer,
    text_engine: *mut sdl3_ttf_sys::ttf::TTF_TextEngine,
    font: *mut sdl3_ttf_sys::ttf::TTF_Font,
) {
    unsafe {
        let (mut w, mut h) = (0, 0);
        sdl3_sys::render::SDL_GetRenderOutputSize(renderer, &mut w, &mut h);

        let c_text = std::ffi::CString::new(text).unwrap();
        let ttf_text = sdl3_ttf_sys::ttf::TTF_CreateText(text_engine, font, c_text.as_ptr(), 0);

        sdl3_sys::everything::SDL_RenderClear(renderer);
        sdl3_ttf_sys::ttf::TTF_DrawRendererText(ttf_text, 20.0, h as f32 / 2.0);
        sdl3_sys::render::SDL_RenderPresent(renderer);
        sdl3_ttf_sys::ttf::TTF_DestroyText(ttf_text);
    }
}
