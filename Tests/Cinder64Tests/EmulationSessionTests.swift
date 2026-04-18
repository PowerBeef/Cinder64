import Foundation
import Testing
@testable import Cinder64

@MainActor
struct EmulationSessionTests {
    @Test func openingAROMStartsTheCoreAndPersistsItAsRecent() async throws {
        let harness = try TemporaryDirectoryHarness()
        let recentGamesStore = RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json"))
        let saveStateStore = SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        let persistence = PersistenceStore(
            recentGamesStore: recentGamesStore,
            saveStateStore: saveStateStore
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Pilotwings 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)

        #expect(core.events == [
            .openROM(romURL),
            .resume,
        ])
        #expect(core.openConfigurations.last?.renderSurface?.viewHandle == 0xFACADE)
        #expect(session.snapshot.emulationState == .running)
        #expect(session.snapshot.activeROM?.displayName == "Pilotwings 64")
        #expect(session.snapshot.rendererName == "Fake Renderer")
        #expect(try recentGamesStore.loadRecords().map(\.identity.displayName) == ["Pilotwings 64"])
    }

    @Test func openingAROMWaitsForTheRenderSurfaceAndShowsBootingState() async throws {
        let harness = try TemporaryDirectoryHarness()
        let recentGamesStore = RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json"))
        let saveStateStore = SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        let persistence = PersistenceStore(
            recentGamesStore: recentGamesStore,
            saveStateStore: saveStateStore
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Star Fox 64.z64")
        try Data("rom-data".utf8).write(to: romURL)

        let launchTask = Task {
            try await session.openROM(url: romURL)
        }

        await Task.yield()

        #expect(core.events.isEmpty)
        #expect(session.snapshot.emulationState == .booting)
        #expect(session.snapshot.activeROM?.displayName == "Star Fox 64")
        #expect(try recentGamesStore.loadRecords().isEmpty)

        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await launchTask.value

        #expect(core.events == [
            .openROM(romURL),
            .resume,
        ])
        #expect(session.snapshot.emulationState == .running)
        #expect(try recentGamesStore.loadRecords().map(\.identity.displayName) == ["Star Fox 64"])
    }

    @Test func recentGamesArePersistedOnlyAfterTheRuntimeReportsReady() async throws {
        let harness = try TemporaryDirectoryHarness()
        let recentGamesStore = RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json"))
        let saveStateStore = SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        let persistence = PersistenceStore(
            recentGamesStore: recentGamesStore,
            saveStateStore: saveStateStore
        )
        let core = FakeCoreHost()
        core.resumeBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Pilotwings 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        let launchTask = Task {
            try await session.openROM(url: romURL)
        }

        while core.resumeRequestCount == 0 {
            await Task.yield()
        }

        #expect(core.events == [
            .openROM(romURL),
            .resume,
        ])
        #expect(try recentGamesStore.loadRecords().isEmpty)

        core.releaseResume()
        try await launchTask.value

        #expect(try recentGamesStore.loadRecords().map(\.identity.displayName) == ["Pilotwings 64"])
    }

    @Test func savingStateUpdatesMetadataForTheSelectedSlot() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Wave Race 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        try await session.saveState(slot: 3)

        let metadata = try persistence.saveStateStore.loadMetadata()

        #expect(core.events.suffix(2) == [.setSaveSlot(3), .saveState])
        #expect(metadata["rom-wave-race-64"]?[3]?.slot == 3)
    }

    @Test func keyboardInputIsForwardedToTheCoreHostOnceAROMIsRunning() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Super Mario 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: false))

        await Task.yield()

        #expect(core.events.suffix(2) == [
            .setKeyboardKey(40, true),
            .setKeyboardKey(40, false),
        ])
    }

    @Test func runtimeTerminationDuringPumpMarksTheSessionAsFailed() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Super Mario 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("The embedded gopher64 runtime exited unexpectedly after boot.")

        session.pumpRuntimeEvents()

        #expect(session.snapshot.emulationState == .failed)
        #expect(session.snapshot.activeROM?.displayName == "Super Mario 64")
        #expect(session.snapshot.warningBanner?.title == "Emulation Stopped Unexpectedly")
        #expect(session.snapshot.warningBanner?.message == "The embedded gopher64 runtime exited unexpectedly after boot.")
    }

    @Test func keyboardInputIsIgnoredAfterTheRuntimeHasFailed() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Super Mario 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            )
        )

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("The embedded gopher64 runtime exited unexpectedly after boot.")
        session.pumpRuntimeEvents()
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))

        await Task.yield()

        #expect(core.events.contains(.setKeyboardKey(40, true)) == false)
    }

}

@MainActor
private final class FakeCoreHost: CoreHosting {
    enum ResumeBehavior {
        case immediate
        case waitForRelease
    }

    enum Event: Equatable {
        case openROM(URL)
        case resume
        case setSaveSlot(Int)
        case saveState
        case setKeyboardKey(Int32, Bool)
    }

    var events: [Event] = []
    var openConfigurations: [CoreHostConfiguration] = []
    var resumeBehavior: ResumeBehavior = .immediate
    var nextPumpEvent: CoreRuntimeEvent?
    private(set) var resumeRequestCount = 0
    private(set) var lastROMIdentity: ROMIdentity?
    private var pendingResumeContinuation: CheckedContinuation<Void, Never>?

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        let identity = try ROMIdentity.make(for: url)
        lastROMIdentity = identity
        events.append(.openROM(url))
        openConfigurations.append(configuration)
        return SessionSnapshot(
            emulationState: .paused,
            activeROM: identity,
            rendererName: "Fake Renderer",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {}

    func pumpEvents() -> CoreRuntimeEvent? {
        defer { nextPumpEvent = nil }
        return nextPumpEvent
    }

    func pause() async throws {}

    func resume() async throws -> SessionSnapshot {
        events.append(.resume)
        resumeRequestCount += 1

        if resumeBehavior == .waitForRelease {
            await withCheckedContinuation { continuation in
                pendingResumeContinuation = continuation
            }
        }

        return SessionSnapshot(
            emulationState: .running,
            activeROM: lastROMIdentity,
            rendererName: "Fake Renderer",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )
    }

    func reset() async throws {}

    func saveState(slot: Int) async throws {
        events.append(.setSaveSlot(slot))
        events.append(.saveState)
    }

    func loadState(slot: Int) async throws {}

    func updateSettings(_ settings: CoreUserSettings) async throws {}

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {}

    func setKeyboardKey(scancode: Int32, pressed: Bool) async throws {
        events.append(.setKeyboardKey(scancode, pressed))
    }

    func stop() async throws {}

    func releaseResume() {
        pendingResumeContinuation?.resume()
        pendingResumeContinuation = nil
    }
}
