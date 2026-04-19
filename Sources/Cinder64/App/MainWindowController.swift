import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    private var pendingWindowedMode: MainWindowDisplayMode?
    var shouldInterceptWindowClose: (() -> Bool)?
    var requestCloseGameForWindowClose: (() -> Void)?
    var onTrackedWindowWillClose: (() -> Void)?
    private var allowsNextWindowClose = false

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
        window.isRestorable = MainWindowLaunchPresentation.restoresPreviousWindowState
        if MainWindowLaunchPresentation.restoresPreviousWindowState == false {
            window.disableSnapshotRestoration()
        }
        window.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
    }

    var currentWindow: NSWindow? {
        window
    }

    var hasTrackedWindow: Bool {
        window != nil
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

    func apply(chromeMode: MainWindowChromeMode) {
        guard let window else { return }

        let configuration = MainWindowChromePresentation.configuration(for: chromeMode)
        window.titleVisibility = configuration.showsVisibleTitle ? .visible : .hidden
        window.toolbarStyle = configuration.usesUnifiedCompactToolbar ? .unifiedCompact : .automatic
    }

    func closeWindowAfterConfirmedClose() {
        guard let window else { return }
        allowsNextWindowClose = true
        window.performClose(nil)
    }

    @discardableResult
    func reopenTrackedWindowIfNeeded() -> Bool {
        guard let window else { return false }

        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsNextWindowClose {
            allowsNextWindowClose = false
            return true
        }

        guard shouldInterceptWindowClose?() == true else {
            return true
        }

        requestCloseGameForWindowClose?()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else {
            return
        }

        onTrackedWindowWillClose?()
        window = nil
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    let displayMode: MainWindowDisplayMode
    let chromeMode: MainWindowChromeMode
    let controller: MainWindowController

    func makeNSView(context: Context) -> MainWindowAccessorView {
        MainWindowAccessorView(
            controller: controller,
            displayMode: displayMode,
            chromeMode: chromeMode
        )
    }

    func updateNSView(_ nsView: MainWindowAccessorView, context: Context) {
        nsView.displayMode = displayMode
        nsView.chromeMode = chromeMode
        nsView.applyWindowPresentationIfPossible()
    }
}

final class MainWindowAccessorView: NSView {
    private weak var controller: MainWindowController?
    var displayMode: MainWindowDisplayMode
    var chromeMode: MainWindowChromeMode

    init(controller: MainWindowController, displayMode: MainWindowDisplayMode, chromeMode: MainWindowChromeMode) {
        self.controller = controller
        self.displayMode = displayMode
        self.chromeMode = chromeMode
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowPresentationIfPossible()
    }

    func applyWindowPresentationIfPossible() {
        guard let window, let controller else { return }
        controller.bind(window: window)
        controller.apply(chromeMode: chromeMode)
        controller.apply(mode: displayMode)
    }
}
