import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject {
    private weak var window: NSWindow?
    private var pendingWindowedMode: MainWindowDisplayMode?

    func bind(window: NSWindow) {
        guard self.window !== window else { return }
        if let currentWindow = self.window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didExitFullScreenNotification,
                object: currentWindow
            )
        }
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func apply(mode: MainWindowDisplayMode) {
        guard let window else {
            if mode.isFullscreen == false {
                pendingWindowedMode = mode
            }
            return
        }

        if mode.isFullscreen {
            enterFullscreen(window: window)
        } else {
            applyWindowedMode(mode, to: window)
        }
    }

    private func enterFullscreen(window: NSWindow) {
        pendingWindowedMode = nil
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(width: 1, height: 1)
        window.contentMaxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        guard window.styleMask.contains(.fullScreen) == false else {
            return
        }

        window.toggleFullScreen(nil)
    }

    private func applyWindowedMode(_ mode: MainWindowDisplayMode, to window: NSWindow) {
        pendingWindowedMode = mode

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            return
        }

        guard let targetSize = MainWindowPresentationPolicy.contentSize(for: mode) else {
            return
        }

        let fittedSize = MainWindowPresentationPolicy.fittedContentSize(
            targetSize,
            visibleFrame: window.screen?.visibleFrame
        )
        window.styleMask.remove(.resizable)
        window.contentMinSize = fittedSize
        window.contentMaxSize = fittedSize
        window.setContentSize(fittedSize)
        window.center()
    }

    @objc private func handleDidExitFullScreen(_: Notification) {
        guard let window, let pendingWindowedMode else { return }
        applyWindowedMode(pendingWindowedMode, to: window)
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    let displayMode: MainWindowDisplayMode
    let controller: MainWindowController

    func makeNSView(context: Context) -> MainWindowAccessorView {
        MainWindowAccessorView(controller: controller, displayMode: displayMode)
    }

    func updateNSView(_ nsView: MainWindowAccessorView, context: Context) {
        nsView.displayMode = displayMode
        nsView.applyDisplayModeIfPossible()
    }
}

final class MainWindowAccessorView: NSView {
    private weak var controller: MainWindowController?
    var displayMode: MainWindowDisplayMode

    init(controller: MainWindowController, displayMode: MainWindowDisplayMode) {
        self.controller = controller
        self.displayMode = displayMode
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyDisplayModeIfPossible()
    }

    func applyDisplayModeIfPossible() {
        guard let window, let controller else { return }
        controller.bind(window: window)
        controller.apply(mode: displayMode)
    }
}
