import AppKit
import SwiftUI

/// SwiftUI placeholder that occupies the gameplay stage area. Its
/// on-screen rect drives the EmulatorDisplayController, which
/// positions the child EmulatorDisplayWindow (the window SDL/MoltenVK
/// actually renders into) to match. SwiftUI sees an empty NSView, so the
/// main window's presentation pipeline stays clean and free of
/// SDL-induced responder/delegate swizzling.
struct EmulatorDisplayAnchorView: NSViewRepresentable {
    let controller: EmulatorDisplayController

    func makeNSView(context: Context) -> EmulatorDisplayAnchorNSView {
        let view = EmulatorDisplayAnchorNSView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: EmulatorDisplayAnchorNSView, context: Context) {
        nsView.controller = controller
        nsView.requestFrameSync()
    }
}

@MainActor
final class EmulatorDisplayAnchorNSView: NSView {
    weak var controller: EmulatorDisplayController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Keep the anchor itself invisible — the child window draws over
        // it. A transparent layer is enough to maintain the SwiftUI
        // layout anchor without producing any visible content.
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            controller?.attach(to: self)
        } else {
            controller?.detach()
        }
    }

    override func layout() {
        super.layout()
        controller?.updateFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        controller?.updateFrame()
    }

    /// Allow updateNSView to request a sync after SwiftUI re-renders
    /// without waiting for a layout pass.
    func requestFrameSync() {
        controller?.updateFrame()
    }

    /// Let clicks on the anchor area pass through to the child emulator
    /// window above. The child window is always composited above the
    /// anchor in screen space, so this path only matters if the child
    /// window is temporarily hidden.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
