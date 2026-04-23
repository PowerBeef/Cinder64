import AppKit

/// Dedicated borderless window that hosts the CAMetalLayer-backed NSView
/// consumed by SDL/MoltenVK. Using a child window (rather than the main
/// SwiftUI window) keeps SDL's swizzling of the NSWindow delegate and Cocoa
/// responder chain isolated from the main window, so SwiftUI sheets and
/// AppKit modals continue to work on the main window unhindered.
///
/// This window is added as a child of the main window via
/// `addChildWindow(_:ordered: .above)`, so it follows the main window's
/// lifecycle (move, miniaturize, close) and participates in fullscreen via
/// `.fullScreenAuxiliary`.
@MainActor
final class EmulatorDisplayWindow: NSWindow {
    /// Title used to identify this auxiliary window when filtering the
    /// app's windows (for example in boot-verification scripts that
    /// count visible windows per PID). The title is never shown in the
    /// UI because the window is borderless.
    static let windowTitle = "Cinder64 Emulator"

    // The emulator child window never becomes key. Keeping the main
    // SwiftUI window as the permanent key window means toolbar
    // buttons, menu shortcuts, and SwiftUI .keyboardShortcut all fire
    // on first click/keystroke — we don't run into macOS's
    // first-mouse activation behavior when the user alternates
    // between the gameplay frame and the toolbar. Keyboard input
    // still reaches the emulator via a gated NSEvent local monitor
    // installed by Cinder64App (see installGameKeyboardMonitor).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        // Use the floating level so the CG window layer is non-zero —
        // boot-verification scripts and any other `kCGWindowLayer == 0`
        // visibility filter treat this auxiliary window as distinct from
        // the main window. Parent/child z-order is maintained by
        // addChildWindow(_:ordered:) in EmulatorDisplayController, so
        // the level doesn't affect in-app composition.
        level = .floating
        isMovable = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        title = Self.windowTitle
    }
}
