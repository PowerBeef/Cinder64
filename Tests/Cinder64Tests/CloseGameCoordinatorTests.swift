import Foundation
import Testing
@testable import Cinder64

@MainActor
struct CloseGameCoordinatorTests {
    @Test func activeGameExitRequestsShowASavePrompt() async throws {
        let harness = try TemporaryDirectoryHarness()
        let session = makeSession(
            harness: harness,
            snapshot: makeSnapshot(name: "Super Mario 64", state: .running)
        )
        let coordinator = CloseGameCoordinator(session: session)

        coordinator.requestCloseGame(.returnHome)

        #expect(coordinator.closePrompt?.intent == .returnHome)
        #expect(coordinator.closePrompt?.canSave == true)
    }

    @Test func failedSessionsAllowClosingButDisableSaving() async throws {
        let harness = try TemporaryDirectoryHarness()
        let session = makeSession(
            harness: harness,
            snapshot: makeSnapshot(name: "Wave Race 64", state: .failed)
        )
        let coordinator = CloseGameCoordinator(session: session)

        coordinator.requestCloseGame(.quitApp)

        #expect(coordinator.closePrompt?.intent == .quitApp)
        #expect(coordinator.closePrompt?.canSave == false)
    }

    @Test func protectedCloseSavePromptsForResumeOnNextLaunch() async throws {
        let harness = try TemporaryDirectoryHarness()
        let session = makeSession(harness: harness, snapshot: .idle)
        let coordinator = CloseGameCoordinator(session: session)
        let romURL = harness.directory.appending(path: "Pilotwings 64.z64")
        try Data("rom-data".utf8).write(to: romURL)
        let identity = try ROMIdentity.make(for: romURL)
        try session.persistenceStore.saveStateStore.recordSaveState(
            for: identity,
            slot: SaveStateMetadataStore.protectedCloseSlot,
            rendererName: "gopher64",
            kind: .protectedClose
        )

        let decision = try coordinator.prepareLaunchRequest(for: romURL)

        #expect(decision == .promptForProtectedResume)
        #expect(coordinator.resumePrompt?.romDisplayName == "Pilotwings 64")
    }

    @Test func closeWithoutSavingStopsTheSessionAndPreservesExitIntent() async throws {
        let harness = try TemporaryDirectoryHarness()
        let core = CloseGameTestCoreHost()
        let session = makeSession(
            harness: harness,
            core: core,
            snapshot: makeSnapshot(name: "Mario Kart 64", state: .running)
        )
        var completedIntent: CloseGameIntent?
        let coordinator = CloseGameCoordinator(
            session: session,
            onConfirmedExit: { intent in
                completedIntent = intent
            }
        )

        coordinator.requestCloseGame(.returnHome)
        await coordinator.closeWithoutSaving()

        #expect(core.events == [.stop])
        #expect(session.snapshot == .idle)
        #expect(completedIntent == .returnHome)
    }

    @Test func saveFailureKeepsThePromptOpenAndReportsTheError() async throws {
        let harness = try TemporaryDirectoryHarness()
        let core = CloseGameTestCoreHost()
        core.saveStateError = NSError(domain: "CloseGameTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Could not save progress."
        ])
        let session = makeSession(
            harness: harness,
            core: core,
            snapshot: makeSnapshot(name: "Star Fox 64", state: .running)
        )
        let coordinator = CloseGameCoordinator(session: session)

        coordinator.requestCloseGame(.returnHome)
        await coordinator.saveAndClose()

        #expect(session.snapshot.activeROM?.displayName == "Star Fox 64")
        #expect(coordinator.closePrompt?.phase == .idle)
        #expect(coordinator.closePrompt?.errorMessage == "Could not save progress.")
    }

    private func makeSession(
        harness: TemporaryDirectoryHarness,
        core: CloseGameTestCoreHost = CloseGameTestCoreHost(),
        snapshot: SessionSnapshot
    ) -> EmulationSession {
        let persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: harness.directory.appending(path: "recent.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        )

        return EmulationSession(
            coreHost: core,
            persistenceStore: persistence,
            snapshot: snapshot
        )
    }

    private func makeSnapshot(name: String, state: EmulationState) -> SessionSnapshot {
        SessionSnapshot(
            emulationState: state,
            activeROM: ROMIdentity(
                id: "rom-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
                fileURL: URL(fileURLWithPath: "/tmp/\(name).z64"),
                displayName: name,
                sha256: "abc123"
            ),
            rendererName: "gopher64",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 1,
            warningBanner: state == .failed ? WarningBanner(title: "Stopped", message: "The runtime exited.") : nil
        )
    }
}

@MainActor
private final class CloseGameTestCoreHost: CoreHosting {
    enum Event: Equatable {
        case setSaveSlot(Int)
        case saveState
        case loadState(Int)
        case stop
    }

    var events: [Event] = []
    var saveStateError: Error?

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        .idle
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {}

    func pumpEvents() -> CoreRuntimeEvent? { nil }

    func pause() async throws {}

    func resume() async throws -> SessionSnapshot { .idle }

    func reset() async throws {}

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

    func updateSettings(_ settings: CoreUserSettings) async throws {}

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {}

    func setKeyboardKey(scancode: Int32, pressed: Bool) async throws {}

    func stop() async throws {
        events.append(.stop)
    }

    func dispose() async throws {}
}
