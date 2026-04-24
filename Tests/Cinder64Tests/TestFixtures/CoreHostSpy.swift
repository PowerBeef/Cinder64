import Foundation
@testable import Cinder64

@MainActor
final class CoreHostSpy: CoreHosting {
    enum ResumeBehavior {
        case immediate
        case waitForRelease
    }

    enum PumpBehavior {
        case immediate
        case waitForRelease
    }

    enum Event: Equatable {
        case openROM(URL)
        case pause
        case resume
        case reset
        case setSaveSlot(Int)
        case saveState
        case loadState(Int)
        case updateSettings(CoreUserSettings)
        case updateInputMapping(InputMappingProfile)
        case enqueueKeyboardEvent(EmbeddedKeyboardEvent)
        case releaseKeyboardInput
        case stop
        case dispose
    }

    var events: [Event] = []
    var openConfigurations: [CoreHostConfiguration] = []
    var surfaceUpdates: [RenderSurfaceDescriptor] = []
    var recordedLifecycleStates: [RuntimeLifecycleState] = []

    var rendererName = "Fake Renderer"
    var resumeBehavior: ResumeBehavior = .immediate
    var pumpBehavior: PumpBehavior = .immediate
    var nextPumpEvent: CoreRuntimeEvent?

    var openError: Error?
    var resumeError: Error?
    var updateRenderSurfaceError: Error?
    var saveStateError: Error?
    var stopError: Error?
    var disposeError: Error?

    private(set) var resumeRequestCount = 0
    private(set) var pumpRequestCount = 0
    private(set) var lastROMIdentity: ROMIdentity?

    private var pendingResumeContinuation: CheckedContinuation<Void, Never>?
    private var pendingPumpContinuation: CheckedContinuation<Void, Never>?

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        if let openError {
            throw openError
        }

        let identity = try ROMIdentity.make(for: url)
        lastROMIdentity = identity
        events.append(.openROM(url))
        recordedLifecycleStates.append(.booting)
        openConfigurations.append(configuration)
        return SessionSnapshot(
            emulationState: .paused,
            activeROM: identity,
            rendererName: rendererName,
            fps: 60,
            videoMode: .windowed,
            audioMuted: configuration.settings.muteAudio,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {
        if let updateRenderSurfaceError {
            throw updateRenderSurfaceError
        }
        surfaceUpdates.append(descriptor)
    }

    func pumpEvents() async -> CoreRuntimeEvent? {
        pumpRequestCount += 1

        if pumpBehavior == .waitForRelease {
            await withCheckedContinuation { continuation in
                pendingPumpContinuation = continuation
            }
        }

        defer { nextPumpEvent = nil }
        return nextPumpEvent
    }

    func pause() async throws {
        events.append(.pause)
    }

    func resume() async throws -> SessionSnapshot {
        if let resumeError {
            throw resumeError
        }

        events.append(.resume)
        resumeRequestCount += 1

        if resumeBehavior == .waitForRelease {
            await withCheckedContinuation { continuation in
                pendingResumeContinuation = continuation
            }
        }

        recordedLifecycleStates.append(.readyPaused)
        recordedLifecycleStates.append(.running)
        return SessionSnapshot(
            emulationState: .running,
            activeROM: lastROMIdentity,
            rendererName: rendererName,
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func reset() async throws {
        events.append(.reset)
    }

    func saveState(slot: Int) async throws {
        if let saveStateError {
            throw saveStateError
        }
        events.append(.setSaveSlot(slot))
        events.append(.saveState)
    }

    func saveProtectedCloseState(slot: Int) async throws {
        try await saveState(slot: slot)
    }

    func loadState(slot: Int) async throws {
        events.append(.loadState(slot))
    }

    func loadProtectedCloseState(slot: Int) async throws {
        events.append(.loadState(slot))
    }

    func updateSettings(_ settings: CoreUserSettings) async throws {
        events.append(.updateSettings(settings))
    }

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {
        events.append(.updateInputMapping(mapping))
    }

    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws {
        events.append(.enqueueKeyboardEvent(event))
    }

    func releaseKeyboardInput() async throws {
        events.append(.releaseKeyboardInput)
    }

    func stop() async throws {
        if let stopError {
            throw stopError
        }
        events.append(.stop)
    }

    func dispose() async throws {
        if let disposeError {
            throw disposeError
        }
        events.append(.dispose)
    }

    func releaseResume() {
        pendingResumeContinuation?.resume()
        pendingResumeContinuation = nil
    }

    func releasePump() {
        pendingPumpContinuation?.resume()
        pendingPumpContinuation = nil
    }
}
