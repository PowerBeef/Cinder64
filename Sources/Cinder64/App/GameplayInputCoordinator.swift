@preconcurrency import AppKit
import Foundation

@MainActor
final class GameplayInputCoordinator {
    typealias AddLocalMonitor = @MainActor (
        NSEvent.EventTypeMask,
        @escaping (NSEvent) -> NSEvent?
    ) -> Any
    typealias RemoveMonitor = @MainActor (Any) -> Void
    typealias EventWindowMatcher = @MainActor (NSEvent, NSWindow?) -> Bool

    private let addLocalMonitor: AddLocalMonitor
    private let removeMonitor: RemoveMonitor
    private let notificationCenter: NotificationCenter
    private let appActiveProvider: () -> Bool
    private let eventWindowMatcher: EventWindowMatcher

    private var monitorToken: Any?
    private weak var trackedWindow: NSWindow?
    private var appObserver: NSObjectProtocol?
    private var trackedWindowObservers: [NSObjectProtocol] = []

    private var eventHandler: ((EmbeddedKeyboardEvent) -> Void)?
    private var releaseHeldInput: (() -> Void)?
    private var emulationState: (() -> EmulationState)?
    private var hasVisiblePrompt: (() -> Bool)?

    init(
        addLocalMonitor: @escaping AddLocalMonitor = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler) as Any
        },
        removeMonitor: @escaping RemoveMonitor = { token in
            NSEvent.removeMonitor(token)
        },
        notificationCenter: NotificationCenter = .default,
        appActiveProvider: @escaping () -> Bool = { NSApp.isActive },
        eventWindowMatcher: @escaping EventWindowMatcher = GameplayInputCoordinator.event(_:matches:)
    ) {
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
        self.notificationCenter = notificationCenter
        self.appActiveProvider = appActiveProvider
        self.eventWindowMatcher = eventWindowMatcher
    }

    func install(
        eventHandler: @escaping (EmbeddedKeyboardEvent) -> Void,
        releaseHeldInput: @escaping () -> Void,
        emulationState: @escaping () -> EmulationState,
        hasVisiblePrompt: @escaping () -> Bool
    ) {
        self.eventHandler = eventHandler
        self.releaseHeldInput = releaseHeldInput
        self.emulationState = emulationState
        self.hasVisiblePrompt = hasVisiblePrompt

        guard monitorToken == nil else {
            return
        }

        monitorToken = addLocalMonitor([.keyDown, .keyUp, .flagsChanged]) { [self] event in
            handle(event)
        }

        appObserver = notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseHeldInputIfPossible()
            }
        }
    }

    func updateTrackedWindow(_ window: NSWindow?) {
        guard trackedWindow !== window else {
            return
        }

        if trackedWindow != nil {
            releaseHeldInputIfPossible()
        }
        tearDownTrackedWindowObservers()
        trackedWindow = window

        guard let window else {
            return
        }

        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            let observer = notificationCenter.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.releaseHeldInputIfPossible()
                }
            }
            trackedWindowObservers.append(observer)
        }
    }

    func promptVisibilityDidChange(isVisible: Bool) {
        if isVisible {
            releaseHeldInputIfPossible()
        }
    }

    func remove() {
        if let monitorToken {
            removeMonitor(monitorToken)
            self.monitorToken = nil
        }

        if let appObserver {
            notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }

        tearDownTrackedWindowObservers()
        releaseHeldInputIfPossible()
        eventHandler = nil
        releaseHeldInput = nil
        emulationState = nil
        hasVisiblePrompt = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let eventHandler,
              let emulationState,
              let hasVisiblePrompt else {
            return event
        }

        let context = GameplayKeyboardInputContext(
            emulationState: emulationState(),
            hasVisiblePrompt: hasVisiblePrompt(),
            isAppActive: appActiveProvider(),
            isEventInTrackedWindow: eventWindowMatcher(event, trackedWindow)
        )

        switch GameplayKeyboardInputPolicy.decision(for: event, context: context) {
        case let .forward(keyboardEvent):
            eventHandler(keyboardEvent)
            return nil
        case .passThrough:
            return event
        }
    }

    private func releaseHeldInputIfPossible() {
        releaseHeldInput?()
    }

    private func tearDownTrackedWindowObservers() {
        for observer in trackedWindowObservers {
            notificationCenter.removeObserver(observer)
        }
        trackedWindowObservers.removeAll()
    }

    private static func event(_ event: NSEvent, matches window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }

        if event.window === window {
            return true
        }

        return event.windowNumber == window.windowNumber
    }
}
