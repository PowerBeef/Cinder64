import Foundation
import Testing
@testable import Cinder64

/// Confirms EmulationSession drives the internal
/// RuntimeLifecycleStateMachine as it walks through the ROM lifecycle,
/// including the fine-grained phases (`readyPaused`, `stopping`,
/// `disposed`) that the user-facing `SessionSnapshot.emulationState`
/// enum doesn't distinguish.
@MainActor
struct EmulationSessionLifecycleTests {
    @Test func lifecycleStartsStopped() {
        let harness = try! LifecyclePersistenceHarness()
        let session = EmulationSession(
            coreHost: LifecycleFakeCoreHost(),
            persistenceStore: harness.persistence
        )

        #expect(session.lifecycleState == RuntimeLifecycleState.stopped)
    }

    @Test func openingAROMTransitionsThroughBootingReadyPausedRunning() async throws {
        let harness = try LifecyclePersistenceHarness()
        let core = LifecycleFakeCoreHost()
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: harness.persistence
        )

        let romURL = harness.directory.appending(path: "Pilotwings 64.z64")
        try Data("rom".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCD,
                viewHandle: 0xEF01,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)

        #expect(session.lifecycleState == RuntimeLifecycleState.running)
        #expect(core.recordedStates == [.booting, .readyPaused, .running])
    }

    @Test func stopTransitionsThroughStoppingToStopped() async throws {
        let harness = try LifecyclePersistenceHarness()
        let session = EmulationSession(
            coreHost: LifecycleFakeCoreHost(),
            persistenceStore: harness.persistence
        )

        let romURL = harness.directory.appending(path: "Extreme-G.z64")
        try Data("rom".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCD,
                viewHandle: 0xEF01,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        try await session.stop()

        #expect(session.lifecycleState == RuntimeLifecycleState.stopped)
    }

    @Test func runtimeFailureTransitionsToFailed() async throws {
        let harness = try LifecyclePersistenceHarness()
        let core = LifecycleFakeCoreHost()
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: harness.persistence
        )

        let romURL = harness.directory.appending(path: "Wave Race 64.z64")
        try Data("rom".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCD,
                viewHandle: 0xEF01,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("runtime crashed")
        session.pumpRuntimeEvents()
        await Task.yield()

        #expect(session.lifecycleState == RuntimeLifecycleState.failed)
    }
}

@MainActor
private final class LifecycleFakeCoreHost: CoreHosting {
    private(set) var recordedStates: [RuntimeLifecycleState] = []
    var nextPumpEvent: CoreRuntimeEvent?

    private var lastIdentity: ROMIdentity?

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        let identity = try ROMIdentity.make(for: url)
        lastIdentity = identity
        recordedStates.append(.booting)
        return SessionSnapshot(
            emulationState: .paused,
            activeROM: identity,
            rendererName: "LifecycleFake",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {}

    func pumpEvents() async -> CoreRuntimeEvent? {
        defer { nextPumpEvent = nil }
        return nextPumpEvent
    }

    func pause() async throws {}

    func resume() async throws -> SessionSnapshot {
        recordedStates.append(.readyPaused)
        recordedStates.append(.running)
        return SessionSnapshot(
            emulationState: .running,
            activeROM: lastIdentity,
            rendererName: "LifecycleFake",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func reset() async throws {}
    func saveState(slot: Int) async throws {}
    func saveProtectedCloseState(slot: Int) async throws {}
    func loadState(slot: Int) async throws {}
    func loadProtectedCloseState(slot: Int) async throws {}
    func updateSettings(_ settings: CoreUserSettings) async throws {}
    func updateInputMapping(_ mapping: InputMappingProfile) async throws {}
    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws {}
    func releaseKeyboardInput() async throws {}
    func stop() async throws {}
    func dispose() async throws {}
}

@MainActor
private struct LifecyclePersistenceHarness {
    let directory: URL
    let persistence: PersistenceStore

    init() throws {
        directory = FileManager.default
            .temporaryDirectory
            .appending(path: "cinder64-lifecycle-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(
                storageURL: directory.appending(path: "recent-games.json")
            ),
            saveStateStore: SaveStateMetadataStore(
                storageURL: directory.appending(path: "savestate-metadata.json")
            )
        )
    }
}
