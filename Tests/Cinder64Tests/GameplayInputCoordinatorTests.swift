import AppKit
import Testing
@testable import Cinder64

@MainActor
@Suite
struct GameplayInputCoordinatorTests {
    @Test func installIsIdempotentAndRemoveReleasesHeldInput() throws {
        let monitor = MonitorRecorder()
        var forwardedEvents: [EmbeddedKeyboardEvent] = []
        var releaseCount = 0
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        let coordinator = GameplayInputCoordinator(
            addLocalMonitor: monitor.addLocalMonitor,
            removeMonitor: monitor.removeMonitor,
            notificationCenter: NotificationCenter(),
            appActiveProvider: { true }
        )

        coordinator.install(
            eventHandler: { forwardedEvents.append($0) },
            releaseHeldInput: { releaseCount += 1 },
            emulationState: { .running },
            hasVisiblePrompt: { false }
        )
        coordinator.install(
            eventHandler: { forwardedEvents.append($0) },
            releaseHeldInput: { releaseCount += 1 },
            emulationState: { .running },
            hasVisiblePrompt: { false }
        )

        #expect(monitor.handlers.count == 1)
        coordinator.updateTrackedWindow(mainWindow)

        let result = withExtendedLifetime(coordinator) {
            monitor.handlers[0](keyEvent(type: .keyDown, keyCode: 0, windowNumber: mainWindow.windowNumber))
        }

        #expect(result == nil)
        #expect(forwardedEvents == [EmbeddedKeyboardEvent(scancode: 4, isPressed: true)])

        coordinator.remove()

        #expect(monitor.removedTokenCount == 1)
        #expect(releaseCount == 1)
    }

    @Test func appAndWindowDeactivationReleaseHeldInput() throws {
        let notificationCenter = NotificationCenter()
        let monitor = MonitorRecorder()
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        var releaseCount = 0
        let coordinator = GameplayInputCoordinator(
            addLocalMonitor: monitor.addLocalMonitor,
            removeMonitor: monitor.removeMonitor,
            notificationCenter: notificationCenter,
            appActiveProvider: { true },
            eventWindowMatcher: { _, _ in true }
        )
        coordinator.install(
            eventHandler: { _ in },
            releaseHeldInput: { releaseCount += 1 },
            emulationState: { .running },
            hasVisiblePrompt: { false }
        )
        coordinator.updateTrackedWindow(mainWindow)

        notificationCenter.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        notificationCenter.post(name: NSWindow.didResignKeyNotification, object: mainWindow)

        #expect(releaseCount == 2)

        coordinator.updateTrackedWindow(nil)
        notificationCenter.post(name: NSWindow.didResignKeyNotification, object: mainWindow)

        #expect(releaseCount == 3)
    }

    @Test func promptPresentationReleasesHeldInput() throws {
        let monitor = MonitorRecorder()
        var releaseCount = 0
        let coordinator = GameplayInputCoordinator(
            addLocalMonitor: monitor.addLocalMonitor,
            removeMonitor: monitor.removeMonitor,
            notificationCenter: NotificationCenter(),
            appActiveProvider: { true },
            eventWindowMatcher: { _, _ in true }
        )
        coordinator.install(
            eventHandler: { _ in },
            releaseHeldInput: { releaseCount += 1 },
            emulationState: { .running },
            hasVisiblePrompt: { false }
        )

        coordinator.promptVisibilityDidChange(isVisible: true)
        coordinator.promptVisibilityDidChange(isVisible: false)

        #expect(releaseCount == 1)
    }

    private func keyEvent(type: NSEvent.EventType, keyCode: UInt16, windowNumber: Int = 1) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

@MainActor
private final class MonitorRecorder {
    var handlers: [(NSEvent) -> NSEvent?] = []
    var removedTokenCount = 0

    func addLocalMonitor(
        matching _: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any {
        handlers.append(handler)
        return NSNumber(value: handlers.count)
    }

    func removeMonitor(_: Any) {
        removedTokenCount += 1
    }
}
