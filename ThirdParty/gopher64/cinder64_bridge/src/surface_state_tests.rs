use crate::{
    BridgeSession,
    HostSurfaceDescriptor,
    JoinOutcome,
    SDLWindowOwnership,
    SurfaceApplyAction,
    determine_surface_apply_action,
    join_with_timeout,
    should_destroy_sdl_window_on_stop,
    update_measured_frame_rate,
};
use std::sync::{Arc, Barrier};
use std::time::{Duration, Instant};

fn make_surface(
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
) -> HostSurfaceDescriptor {
    HostSurfaceDescriptor {
        surface_id,
        generation,
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
    let incoming = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 1);

    let action = determine_surface_apply_action(None, &incoming);

    assert_eq!(action, SurfaceApplyAction::Attach);
}

#[test]
fn identical_revision_is_a_no_op() {
    let applied = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::NoOp);
}

#[test]
fn pixel_size_change_is_a_resize() {
    let applied = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(1, 1, 0xCAFE, 0xBEEF, 700, 500, 1400, 1000, 2.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Resize);
}

#[test]
fn handle_change_requires_reattach() {
    let applied = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(1, 2, 0xFACE, 0xD00D, 640, 480, 1280, 960, 2.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Reattach);
}

#[test]
fn scale_change_still_uses_resize() {
    let applied = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1280, 960, 2.0, 3);
    let incoming = make_surface(1, 1, 0xCAFE, 0xBEEF, 640, 480, 1920, 1440, 3.0, 4);

    let action = determine_surface_apply_action(Some(&applied), &incoming);

    assert_eq!(action, SurfaceApplyAction::Resize);
}

#[test]
fn invalid_descriptor_is_rejected_cleanly() {
    let invalid = make_surface(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0);

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
    assert_eq!(session.render_frame_count, 58);
    assert_eq!(session.present_count, 58);
    assert_eq!(session.vi_count, 60);
}

#[test]
fn join_with_timeout_reports_completed_when_thread_exits_in_time() {
    let handle = std::thread::spawn(|| {});
    assert_eq!(
        join_with_timeout(handle, Duration::from_secs(1)),
        JoinOutcome::Completed
    );
}

#[test]
fn join_with_timeout_reports_panicked_when_thread_panics() {
    let handle = std::thread::spawn(|| {
        // Panics intentionally to exercise the panic branch.
        panic!("intentional test panic");
    });
    assert_eq!(
        join_with_timeout(handle, Duration::from_secs(1)),
        JoinOutcome::Panicked
    );
}

#[test]
fn join_with_timeout_reports_timeout_for_wedged_thread() {
    let release = Arc::new(Barrier::new(2));
    let release_worker = Arc::clone(&release);
    let handle = std::thread::spawn(move || {
        // Park here until the test unblocks us. This mirrors an emulation
        // thread stuck in a blocking Vulkan present.
        release_worker.wait();
    });

    let started_at = Instant::now();
    let outcome = join_with_timeout(handle, Duration::from_millis(300));
    let elapsed = started_at.elapsed();

    assert_eq!(outcome, JoinOutcome::TimedOut);
    // The join must not have spent much longer than the requested timeout.
    assert!(
        elapsed < Duration::from_millis(1_500),
        "join_with_timeout took {:?} — expected to return close to the 300ms budget",
        elapsed
    );

    // Unblock the leaked thread so it can exit cleanly after the test.
    release.wait();
}
