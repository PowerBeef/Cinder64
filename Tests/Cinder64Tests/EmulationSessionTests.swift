import Foundation
import Testing
@testable import Cinder64

@MainActor
@Suite
struct EmulationSessionTests {
    @Test func openingAROMStartsTheCoreAndPersistsItAsRecent() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Pilotwings 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)

        #expect(core.events == [.openROM(romURL), .resume])
        #expect(core.openConfigurations.last?.renderSurface?.viewHandle == 0xFACADE)
        #expect(session.snapshot.emulationState == .running)
        #expect(session.snapshot.activeROM?.displayName == "Pilotwings 64")
        #expect(session.snapshot.rendererName == "Fake Renderer")
        #expect(try persistence.persistence.recentGamesStore.loadRecords().map(\.identity.displayName) == ["Pilotwings 64"])
    }

    @Test func openingAROMWaitsForTheRenderSurfaceAndShowsBootingState() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Star Fox 64.z64", in: persistence.directory)

        let launchTask = Task {
            try await session.openROM(url: romURL)
        }

        await yieldToQueuedTasks()

        #expect(core.events.isEmpty)
        #expect(session.snapshot.emulationState == .booting)
        #expect(session.snapshot.activeROM?.displayName == "Star Fox 64")
        #expect(try persistence.persistence.recentGamesStore.loadRecords().isEmpty)

        session.updateRenderSurface(.testSurface())
        try await launchTask.value

        #expect(core.events == [.openROM(romURL), .resume])
        #expect(session.snapshot.emulationState == .running)
        #expect(try persistence.persistence.recentGamesStore.loadRecords().map(\.identity.displayName) == ["Star Fox 64"])
    }

    @Test func openingAROMTimesOutWhenTheRenderSurfaceNeverArrives() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: persistence.persistence,
            renderSurfaceWaitTimeout: .milliseconds(10)
        )
        let romURL = try ROMFixture.writeROM(named: "No Surface.z64", in: persistence.directory)

        await #expect(throws: EmulationSessionError.renderSurfaceUnavailable) {
            try await session.openROM(url: romURL)
        }

        #expect(core.events.isEmpty)
        #expect(session.snapshot == .idle)

        session.updateRenderSurface(.testSurface())
        await yieldToQueuedTasks()

        #expect(core.events.isEmpty)
    }

    @Test func recentGamesArePersistedOnlyAfterTheRuntimeReportsReady() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        core.resumeBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Pilotwings 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        let launchTask = Task {
            try await session.openROM(url: romURL)
        }

        await waitForCondition("resume request") {
            core.resumeRequestCount == 1
        }

        #expect(core.events == [.openROM(romURL), .resume])
        #expect(try persistence.persistence.recentGamesStore.loadRecords().isEmpty)

        core.releaseResume()
        try await launchTask.value

        #expect(try persistence.persistence.recentGamesStore.loadRecords().map(\.identity.displayName) == ["Pilotwings 64"])
    }

    @Test func renderSurfaceChangesDuringBootAreReplayedAfterTheSessionStartsRunning() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        core.resumeBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "F-Zero X.z64", in: persistence.directory)

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

        await waitForCondition("resume request") {
            core.resumeRequestCount == 1
        }

        #expect(session.snapshot.emulationState == .booting)
        #expect(core.openConfigurations.last?.renderSurface == initialSurface)

        session.updateRenderSurface(settledSurface)
        core.releaseResume()

        try await launchTask.value
        await yieldToQueuedTasks()

        #expect(session.snapshot.emulationState == .running)
        #expect(core.surfaceUpdates == [settledSurface])
    }

    @Test func runtimeFrameRateUpdatesRefreshTheSessionSnapshot() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Mario Kart 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .frameRateUpdated(52.4)

        session.pumpRuntimeEvents()
        await yieldToQueuedTasks()

        #expect(session.snapshot.fps == 52.4)
    }

    @Test func savingStateUpdatesMetadataForTheSelectedSlot() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Wave Race 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        try await session.saveState(slot: 3)

        let metadata = try persistence.persistence.saveStateStore.loadMetadata()

        #expect(core.events.suffix(2) == [.setSaveSlot(3), .saveState])
        let identityID = try #require(session.snapshot.activeROM?.id)
        #expect(metadata[identityID]?[3]?.slot == 3)
    }

    @Test func savingProtectedCloseStateUsesTheReservedSlotWithoutChangingTheManualSlot() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "1080 Snowboarding.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        try await session.saveProtectedCloseState()

        let metadata = try persistence.persistence.saveStateStore.loadMetadata()

        #expect(core.events.suffix(2) == [.setSaveSlot(SaveStateMetadataStore.protectedCloseSlot), .saveState])
        let identityID = try #require(session.snapshot.activeROM?.id)
        #expect(metadata[identityID]?[SaveStateMetadataStore.protectedCloseSlot]?.kind == .protectedClose)
        #expect(session.snapshot.activeSaveSlot == 0)
    }

    @Test func keyboardInputIsForwardedToTheCoreHostOnceAROMIsRunning() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Super Mario 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: false))

        await yieldToQueuedTasks()

        #expect(core.events.suffix(2) == [
            .enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: true)),
            .enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: false)),
        ])
    }

    @Test func keyboardInputWithoutAnActiveROMIsIgnoredAndLogged() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)

        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))

        await yieldToQueuedTasks()

        #expect(core.events.isEmpty)
        #expect(try persistence.logText().contains("keyboard input ignored: no active ROM"))
    }

    @Test func runtimeTerminationDuringPumpMarksTheSessionAsFailed() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Super Mario 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("The embedded gopher64 runtime exited unexpectedly after boot.")

        session.pumpRuntimeEvents()
        await yieldToQueuedTasks()

        #expect(session.snapshot.emulationState == .failed)
        #expect(session.snapshot.activeROM?.displayName == "Super Mario 64")
        #expect(session.snapshot.warningBanner?.title == "Emulation Stopped Unexpectedly")
        #expect(session.snapshot.warningBanner?.message == "The embedded gopher64 runtime exited unexpectedly after boot.")
    }

    @Test func renderSurfaceUpdateFailuresAreSurfaced() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Super Mario 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

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

        await yieldToQueuedTasks()

        #expect(session.snapshot.emulationState == .failed)
        #expect(session.snapshot.warningBanner?.message == "Surface sync failed.")
        #expect(try persistence.logText().contains("render-surface update failed revision=2"))
    }

    @Test func keyboardInputIsIgnoredAfterTheRuntimeHasFailed() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Super Mario 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("The embedded gopher64 runtime exited unexpectedly after boot.")
        session.pumpRuntimeEvents()
        session.handleKeyboardInput(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))

        await yieldToQueuedTasks()

        #expect(core.events.contains(.enqueueKeyboardEvent(EmbeddedKeyboardEvent(scancode: 40, isPressed: true))) == false)
        #expect(try persistence.logText().contains("keyboard input ignored: emulationState=failed"))
    }

    @Test func releasingKeyboardInputForwardsAReleaseAllRequestToTheCoreHost() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Wave Race 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        session.releaseKeyboardInput()

        await yieldToQueuedTasks()

        #expect(core.events.suffix(1) == [.releaseKeyboardInput])
    }

    @Test func runtimePumpsAreSerializedWhileAPumpIsAlreadyInFlight() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        core.pumpBehavior = .waitForRelease
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "F-Zero X.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        session.pumpRuntimeEvents()
        session.pumpRuntimeEvents()

        await waitForCondition("first pump request") {
            core.pumpRequestCount == 1
        }

        #expect(core.pumpRequestCount == 1)

        core.releasePump()
        await yieldToQueuedTasks()
        session.pumpRuntimeEvents()
        await yieldToQueuedTasks()

        #expect(core.pumpRequestCount == 2)
    }

    @Test func stoppingAnActiveSessionReturnsToTheLauncherShellWithoutDisposingTheCoreHost() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let romURL = try ROMFixture.writeROM(named: "Mario Kart 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        try await session.stop()

        #expect(core.events.suffix(4) == [.openROM(romURL), .resume, .releaseKeyboardInput, .stop])
        #expect(core.events.contains(.dispose) == false)
        #expect(session.snapshot == .idle)
        #expect(ShellPresentation.mode(for: session.snapshot) == .homeDashboard)
    }

    @Test func disposingTheSessionTearsDownTheDormantCoreHost() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)

        try await session.dispose()

        #expect(core.events == [.dispose])
        #expect(session.snapshot == .idle)
    }
}
