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

    @Test func renderSurfaceChangesDuringBootAreReplayedAfterTheSessionStartsRunning() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        core.resumeBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "F-Zero X.z64")
        try Data("rom-data".utf8).write(to: romURL)

        let initialSurface = RenderSurfaceDescriptor(
            windowHandle: 0xABCDABCD,
            viewHandle: 0xFACADE,
            logicalWidth: 624,
            logicalHeight: 431,
            pixelWidth: 1248,
            pixelHeight: 862,
            backingScaleFactor: 2,
            revision: 1
        )
        let settledSurface = RenderSurfaceDescriptor(
            windowHandle: 0xABCDABCD,
            viewHandle: 0xFACADE,
            logicalWidth: 900,
            logicalHeight: 580,
            pixelWidth: 1800,
            pixelHeight: 1160,
            backingScaleFactor: 2,
            revision: 2
        )

        session.updateRenderSurface(initialSurface)

        let launchTask = Task {
            try await session.openROM(url: romURL)
        }

        while core.resumeRequestCount == 0 {
            await Task.yield()
        }

        #expect(session.snapshot.emulationState == .booting)
        #expect(core.openConfigurations.last?.renderSurface == initialSurface)

        session.updateRenderSurface(settledSurface)
        core.releaseResume()

        try await launchTask.value
        await Task.yield()

        #expect(session.snapshot.emulationState == .running)
        #expect(core.surfaceUpdates == [settledSurface])
    }

    @Test func runtimeFrameRateUpdatesRefreshTheSessionSnapshot() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Mario Kart 64.z64")
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
        core.nextPumpEvent = .frameRateUpdated(52.4)

        session.pumpRuntimeEvents()
        await Task.yield()

        #expect(session.snapshot.fps == 52.4)
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

    @Test func savingProtectedCloseStateUsesTheReservedSlotWithoutChangingTheManualSlot() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "1080 Snowboarding.z64")
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
        try await session.saveProtectedCloseState()

        let metadata = try persistence.saveStateStore.loadMetadata()

        #expect(core.events.suffix(2) == [.setSaveSlot(SaveStateMetadataStore.protectedCloseSlot), .saveState])
        #expect(metadata["rom-1080-snowboarding"]?[SaveStateMetadataStore.protectedCloseSlot]?.kind == .protectedClose)
        #expect(session.snapshot.activeSaveSlot == 0)
    }

    @Test func keyboardInputIsForwardedToTheCoreHostOnceAROMIsRunning() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json")),
            logStore: LogStore(logFileURL: harness.directory.appending(path: "runtime.log"))
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
            .enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: true)),
            .enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: false)),
        ])
    }

    @Test func keyboardInputWithoutAnActiveROMIsIgnoredAndLogged() async throws {
        let harness = try TemporaryDirectoryHarness()
        let logURL = harness.directory.appending(path: "runtime.log")
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json")),
            logStore: LogStore(logFileURL: logURL)
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)

        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))

        await Task.yield()

        #expect(core.events.isEmpty)
        #expect(try String(contentsOf: logURL, encoding: .utf8).contains("keyboard input ignored: no active ROM"))
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
        await Task.yield()

        #expect(session.snapshot.emulationState == .failed)
        #expect(session.snapshot.activeROM?.displayName == "Super Mario 64")
        #expect(session.snapshot.warningBanner?.title == "Emulation Stopped Unexpectedly")
        #expect(session.snapshot.warningBanner?.message == "The embedded gopher64 runtime exited unexpectedly after boot.")
    }

    @Test func renderSurfaceUpdateFailuresAreSurfaced() async throws {
        let harness = try TemporaryDirectoryHarness()
        let logURL = harness.directory.appending(path: "runtime.log")
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json")),
            logStore: LogStore(logFileURL: logURL)
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
        core.updateRenderSurfaceError = NSError(
            domain: "RenderSurfaceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Surface sync failed."]
        )

        session.updateRenderSurface(
            RenderSurfaceDescriptor(
                windowHandle: 0xABCDABCD,
                viewHandle: 0xFACADE,
                logicalWidth: 1400,
                logicalHeight: 800,
                pixelWidth: 2800,
                pixelHeight: 1600,
                backingScaleFactor: 2,
                revision: 2
            )
        )

        await Task.yield()

        #expect(session.snapshot.emulationState == .failed)
        #expect(session.snapshot.warningBanner?.message == "Surface sync failed.")
        #expect(try String(contentsOf: logURL, encoding: .utf8).contains("render-surface update failed revision=2"))
    }

    @Test func keyboardInputIsIgnoredAfterTheRuntimeHasFailed() async throws {
        let harness = try TemporaryDirectoryHarness()
        let logURL = harness.directory.appending(path: "runtime.log")
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json")),
            logStore: LogStore(logFileURL: logURL)
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

        #expect(core.events.contains(.enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))) == false)
        #expect(try String(contentsOf: logURL, encoding: .utf8).contains("keyboard input ignored: emulationState=failed"))
    }

    @Test func releasingKeyboardInputForwardsAReleaseAllRequestToTheCoreHost() async throws {
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
        session.releaseKeyboardInput()

        await Task.yield()

        #expect(core.events.suffix(1) == [.releaseKeyboardInput])
    }

    @Test func runtimePumpsAreSerializedWhileAPumpIsAlreadyInFlight() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        core.pumpBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "F-Zero X.z64")
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
        session.pumpRuntimeEvents()
        session.pumpRuntimeEvents()

        await Task.yield()

        #expect(core.pumpRequestCount == 1)

        core.releasePump()
        await Task.yield()
        session.pumpRuntimeEvents()
        await Task.yield()

        #expect(core.pumpRequestCount == 2)
    }

    @Test func stoppingAnActiveSessionReturnsToTheLauncherShellWithoutDisposingTheCoreHost() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)
        let romURL = harness.directory.appending(path: "Mario Kart 64.z64")
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
        try await session.stop()

        #expect(core.events.suffix(3) == [.openROM(romURL), .resume, .stop])
        #expect(core.events.contains(.dispose) == false)
        #expect(session.snapshot == .idle)
        #expect(ShellPresentation.mode(for: session.snapshot) == .homeDashboard)
    }

    @Test func disposingTheSessionTearsDownTheDormantCoreHost() async throws {
        let harness = try TemporaryDirectoryHarness()
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )
        let core = FakeCoreHost()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence)

        try await session.dispose()

        #expect(core.events == [.dispose])
        #expect(session.snapshot == .idle)
    }
}

@MainActor
private final class FakeCoreHost: CoreHosting {
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
        case resume
        case setSaveSlot(Int)
        case saveState
        case enqueueKeyboardEvent(EmbeddedKeyboardEvent)
        case releaseKeyboardInput
        case stop
        case dispose
    }

    var events: [Event] = []
    var openConfigurations: [CoreHostConfiguration] = []
    var surfaceUpdates: [RenderSurfaceDescriptor] = []
    var resumeBehavior: ResumeBehavior = .immediate
    var pumpBehavior: PumpBehavior = .immediate
    var nextPumpEvent: CoreRuntimeEvent?
    var updateRenderSurfaceError: Error?
    private(set) var resumeRequestCount = 0
    private(set) var pumpRequestCount = 0
    private(set) var lastROMIdentity: ROMIdentity?
    private var pendingResumeContinuation: CheckedContinuation<Void, Never>?
    private var pendingPumpContinuation: CheckedContinuation<Void, Never>?

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

    func saveProtectedCloseState(slot: Int) async throws {
        events.append(.setSaveSlot(slot))
        events.append(.saveState)
    }

    func loadState(slot: Int) async throws {}

    func loadProtectedCloseState(slot: Int) async throws {}

    func updateSettings(_ settings: CoreUserSettings) async throws {}

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {}

    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws {
        events.append(.enqueueKeyboardEvent(event))
    }

    func releaseKeyboardInput() async throws {
        events.append(.releaseKeyboardInput)
    }

    func stop() async throws {
        events.append(.stop)
    }

    func dispose() async throws {
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
