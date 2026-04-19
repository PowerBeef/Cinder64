use crate::{
    BridgeSession,
    HostSurfaceDescriptor,
    SDLWindowOwnership,
    SurfaceApplyAction,
    determine_surface_apply_action,
    should_destroy_sdl_window_on_stop,
    update_measured_frame_rate,
};
use std::time::{Duration, Instant};

fn make_surface(
    window_handle: usize,
    view_handle: usize,
    logical_width: i32,
    logical_height: i32,
    pixel_width: u32,
    pixel_height: u32,
    backing_scale_factor: f64,
    revision: u64,
) -> HostSurfaceDescriptor {
    HostSurfaceDescriptor {
        window_handle,
        view_handle,
        logical_width,
        logical_height,
        pixel_width,
        pixel_height,
        backing_scale_factor,
        revision,
    }
}

#[test]
fn initial_surface_requires_attach() {
    let incoming = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 1);

    let action = determine_surface_apply_action(None, &incoming);

    assert_eq!(action, SurfaceApplyAction::Attach);
}

#[test]
fn identical_revision_is_a_no_op() {
    let applied = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::NoOp);
}

#[test]
fn pixel_size_change_is_a_resize() {
    let applied = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(0xCAFE, 0xBEEF, 700, 500, 1400, 1000, 2.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Resize);
}

#[test]
fn handle_change_requires_reattach() {
    let applied = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(0xFACE, 0xD00D, 640, 480, 1280, 960, 2.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Reattach);
}

#[test]
fn scale_change_still_uses_resize() {
    let applied = make_surface(0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(0xCAFE, 0xBEEF, 640, 480, 1920, 1440, 3.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Resize);
}

#[test]
fn invalid_descriptor_is_rejected_cleanly() {
    let invalid = make_surface(0, 0, 0, 0, 0, 0, 0.0, 0);

    assert!(!invalid.is_valid());
}

#[test]
fn host_owned_sdl_windows_are_preserved_when_stopping() {
    assert!(!should_destroy_sdl_window_on_stop(SDLWindowOwnership::HostOwned));
}

#[test]
fn runtime_owned_sdl_windows_are_destroyed_when_stopping() {
    assert!(should_destroy_sdl_window_on_stop(SDLWindowOwnership::RuntimeOwned));
}

#[test]
fn measured_frame_rate_updates_after_a_one_second_sample_window() {
    let mut session = BridgeSession::new();
    let sample_start = Instant::now() - Duration::from_secs(1);
    session.last_metrics_sample_at = Some(sample_start);

    let frame_rate = update_measured_frame_rate(
        &mut session,
        sample_start + Duration::from_millis(1_000),
        (58, 60),
    );

    assert_eq!(frame_rate, Some(58.0));
    assert_eq!(session.frame_rate, 58.0);
}
