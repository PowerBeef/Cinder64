import Foundation
import Testing
@testable import Cinder64

@MainActor
@Suite
struct CloseGameCoordinatorTests {
    @Test(
        "Exit requests produce the expected prompt",
        arguments: [
            ClosePromptCase(name: "Super Mario 64", state: .running, intent: .returnHome, canSave: true),
            ClosePromptCase(name: "Wave Race 64", state: .failed, intent: .quitApp, canSave: false),
        ]
    )
    func exitRequestsProduceTheExpectedPrompt(_ testCase: ClosePromptCase) async throws {
        let session = try makeSession(snapshot: makeSnapshot(name: testCase.name, state: testCase.state))
        let coordinator = CloseGameCoordinator(session: session)

        coordinator.requestCloseGame(testCase.intent)

        #expect(coordinator.closePrompt?.intent == testCase.intent)
        #expect(coordinator.closePrompt?.canSave == testCase.canSave)
    }

    @Test func protectedCloseSavePromptsForResumeOnNextLaunch() async throws {
        let persistence = try PersistenceFixture()
        let session = EmulationSession(
            coreHost: CoreHostSpy(),
            persistenceStore: persistence.persistence,
            snapshot: .idle
        )
        let coordinator = CloseGameCoordinator(session: session)
        let romURL = try ROMFixture.writeROM(named: "Pilotwings 64.z64", in: persistence.directory)
        let identity = try ROMIdentity.make(for: romURL)
        try session.persistenceStore.saveStateStore.recordSaveState(
            for: identity,
            slot: SaveStateMetadataStore.protectedCloseSlot,
            rendererName: "gopher64",
            kind: .protectedClose
        )

        let decision = try await coordinator.prepareLaunchRequest(for: romURL)

        #expect(decision == .promptForProtectedResume)
        #expect(coordinator.resumePrompt?.romDisplayName == "Pilotwings 64")
    }

    @Test func closeWithoutSavingStopsTheSessionAndPreservesExitIntent() async throws {
        let core = CoreHostSpy()
        let session = try makeSession(
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

        #expect(core.events == [.releaseKeyboardInput, .stop])
        #expect(session.snapshot == .idle)
        #expect(completedIntent == .returnHome)
    }

    @Test func saveFailureKeepsThePromptOpenAndReportsTheError() async throws {
        let core = CoreHostSpy()
        core.saveStateError = NSError(domain: "CloseGameTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Could not save progress."
        ])
        let session = try makeSession(
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
        core: CoreHostSpy = CoreHostSpy(),
        snapshot: SessionSnapshot
    ) throws -> EmulationSession {
        let persistence = try PersistenceFixture(prefix: "cinder64-close-game")
        return EmulationSession(
            coreHost: core,
            persistenceStore: persistence.persistence,
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

struct ClosePromptCase: Sendable {
    let name: String
    let state: EmulationState
    let intent: CloseGameIntent
    let canSave: Bool
}
