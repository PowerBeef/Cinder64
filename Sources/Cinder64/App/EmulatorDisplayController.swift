import AppKit
import OSLog
import SwiftUI

/// Coordinates the dedicated EmulatorDisplayWindow that hosts the SDL /
/// MoltenVK render surface. Keeps the child window's frame locked to the
/// anchor NSView placed by the SwiftUI gameplay shell, and manages
/// attachment as a child of the main window so it follows move, resize,
/// miniaturize, and fullscreen transitions.
@MainActor
final class EmulatorDisplayController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.patricedery.Cinder64",
        category: "EmulatorDisplay"
    )

    let window: EmulatorDisplayWindow
    let surfaceView: EmulatorDisplaySurfaceView

    private weak var anchorView: NSView?
    private weak var parentWindow: NSWindow?
    private var parentWindowObservers: [NSObjectProtocol] = []
    private var isAttached = false
    private var overlayHostingView: NSHostingView<AnyView>?
    private var currentOverlayContent: SurfaceOverlayContent?

    init() {
        let surfaceView = EmulatorDisplaySurfaceView(frame: .zero)
        self.surfaceView = surfaceView
        let window = EmulatorDisplayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480)
        )

        // The emulator window's contentView is a plain container that
        // hosts the SDL-consumed surface view AND an optional overlay
        // NSHostingView. Using a container lets us stack a SwiftUI
        // overlay above the Metal surface reliably — NSHostingView
        // composites with normal CoreAnimation ordering inside this
        // window, which SwiftUI sheets on the main window can't do
        // above SDL's Metal output.
        let containerView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        containerView.wantsLayer = true
        containerView.autoresizesSubviews = true
        surfaceView.autoresizingMask = [.width, .height]
        surfaceView.frame = containerView.bounds
        containerView.addSubview(surfaceView)
        window.contentView = containerView

        self.window = window
    }

    /// Attach the emulator display window as a child of the anchor's
    /// window and start tracking the anchor's screen rect.
    func attach(to anchor: NSView) {
        let newParent = anchor.window
        let parentChanged = parentWindow !== newParent

        anchorView = anchor

        if parentChanged {
            tearDownParentObservers()
            if let currentParent = parentWindow,
               window.parent === currentParent {
                currentParent.removeChildWindow(window)
            }
            parentWindow = newParent
            if let newParent {
                newParent.addChildWindow(window, ordered: .above)
                registerParentObservers(on: newParent)
            }
        } else if let newParent, window.parent !== newParent {
            newParent.addChildWindow(window, ordered: .above)
        }

        isAttached = true
        updateFrame()
    }

    /// Stop tracking the anchor and hide the child window.
    func detach() {
        isAttached = false
        tearDownParentObservers()
        if let parent = parentWindow, window.parent === parent {
            parent.removeChildWindow(window)
        }
        window.orderOut(nil)
        anchorView = nil
        parentWindow = nil
    }

    /// Recompute the child window's frame from the anchor's current
    /// position in its parent window. Called on layout, on every
    /// parent-window geometry change, and explicitly from the anchor
    /// representable when it re-lays out.
    func updateFrame() {
        guard isAttached, let anchor = anchorView, let parent = parentWindow else {
            return
        }

        let anchorBoundsInWindow = anchor.convert(anchor.bounds, to: nil)
        let screenFrame = parent.convertToScreen(anchorBoundsInWindow)

        guard screenFrame.width >= 1, screenFrame.height >= 1 else {
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }

        if window.frame != screenFrame {
            window.setFrame(screenFrame, display: true)
        }

        if window.isVisible == false {
            window.orderFront(nil)
        }
    }

    /// Update the state-transition overlay (booting / paused / failed /
    /// etc.) hosted inside the emulator window so it renders above the
    /// Vulkan frame. Passing a snapshot whose state yields nil from
    /// SurfaceOverlayPresentation hides any existing overlay.
    func updateOverlay(for snapshot: SessionSnapshot) {
        let newContent = SurfaceOverlayPresentation.content(for: snapshot)

        guard newContent != currentOverlayContent else { return }
        currentOverlayContent = newContent

        if let newContent {
            installOverlay(newContent)
        } else {
            removeOverlay()
        }
    }

    private func installOverlay(_ content: SurfaceOverlayContent) {
        guard let container = window.contentView else { return }

        let rootView = AnyView(
            ZStack {
                SurfaceOverlayCard(content: content)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        )

        if let existing = overlayHostingView {
            existing.rootView = rootView
            existing.frame = container.bounds
            existing.autoresizingMask = [.width, .height]
            existing.needsDisplay = true
            return
        }

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        // Let clicks fall through the overlay area; the user can't
        // interact with a booting / failed / paused card anyway.
        container.addSubview(hosting, positioned: .above, relativeTo: surfaceView)
        overlayHostingView = hosting
    }

    private func removeOverlay() {
        overlayHostingView?.removeFromSuperview()
        overlayHostingView = nil
    }

    private func registerParentObservers(on parent: NSWindow) {
        let center = NotificationCenter.default
        let notifications: [NSNotification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeScreenNotification,
        ]

        for name in notifications {
            let observer = center.addObserver(
                forName: name,
                object: parent,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateFrame()
                }
            }
            parentWindowObservers.append(observer)
        }
    }

    private func tearDownParentObservers() {
        let center = NotificationCenter.default
        for observer in parentWindowObservers {
            center.removeObserver(observer)
        }
        parentWindowObservers.removeAll()
    }
}
