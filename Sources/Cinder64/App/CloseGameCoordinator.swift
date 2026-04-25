import Foundation
import Observation

enum CloseGameIntent: String, Equatable, Sendable {
    case returnHome
    case closeWindow
    case quitApp
}

enum CloseGameLaunchRequestDecision: Equatable, Sendable {
    case launchNormally
    case promptForProtectedResume
}

enum CloseGamePromptPhase: Equatable, Sendable {
    case idle
    case saving
    case closing
}

struct CloseGamePromptState: Identifiable, Equatable, Sendable {
    let intent: CloseGameIntent
    let romDisplayName: String
    let canSave: Bool
    var phase: CloseGamePromptPhase
    var errorMessage: String?

    var id: String {
        "\(intent.rawValue)-\(romDisplayName)"
    }
}

struct ResumeProtectedSavePromptState: Identifiable, Equatable, Sendable {
    let romDisplayName: String

    var id: String {
        romDisplayName
    }
}

struct PendingProtectedLaunch: Equatable, Sendable {
    let url: URL
    let shouldResumeProtectedSave: Bool
}

@MainActor
@Observable
final class CloseGameCoordinator {
    private let session: EmulationSession
    private var pendingLaunchURL: URL?

    var closePrompt: CloseGamePromptState?
    var resumePrompt: ResumeProtectedSavePromptState?
    var onConfirmedExit: ((CloseGameIntent) -> Void)?

    init(
        session: EmulationSession,
        onConfirmedExit: ((CloseGameIntent) -> Void)? = nil
    ) {
        self.session = session
        self.onConfirmedExit = onConfirmedExit
    }

    var shouldInterceptExitRequests: Bool {
        session.snapshot.activeROM != nil
    }

    func requestCloseGame(_ intent: CloseGameIntent) {
        guard let activeROM = session.snapshot.activeROM else {
            session.persistenceStore.logStore.record("warning", "close-game request ignored intent=\(intent.rawValue) because no active ROM is present")
            return
        }
        guard closePrompt == nil else {
            session.persistenceStore.logStore.record("info", "close-game request ignored intent=\(intent.rawValue) because a prompt is already visible")
            return
        }

        session.persistenceStore.logStore.record("info", "close-game requested intent=\(intent.rawValue) rom=\(activeROM.displayName)")

        setClosePrompt(CloseGamePromptState(
            intent: intent,
            romDisplayName: activeROM.displayName,
            canSave: canSaveCurrentSession,
            phase: .idle,
            errorMessage: nil
        ))
    }

    func cancelCloseGame() {
        setClosePrompt(nil)
    }

    func saveAndClose() async {
        guard var prompt = closePrompt, prompt.canSave else { return }
        prompt.phase = .saving
        prompt.errorMessage = nil
        setClosePrompt(prompt)

        do {
            try await session.saveProtectedCloseState()
            await completeClose(using: prompt.intent)
        } catch {
            prompt.phase = .idle
            prompt.errorMessage = error.localizedDescription
            setClosePrompt(prompt)
        }
    }

    func closeWithoutSaving() async {
        guard let prompt = closePrompt else { return }
        await completeClose(using: prompt.intent)
    }

    func prepareLaunchRequest(for url: URL) async throws -> CloseGameLaunchRequestDecision {
        let identity = try await session.resolveROMIdentity(for: url)
        guard try session.persistenceStore.saveStateStore.hasProtectedCloseSave(for: identity) else {
            return .launchNormally
        }

        pendingLaunchURL = url
        setResumePrompt(ResumeProtectedSavePromptState(romDisplayName: identity.displayName))
        return .promptForProtectedResume
    }

    func resolvePendingLaunch(shouldResumeProtectedSave: Bool) -> PendingProtectedLaunch? {
        guard let pendingLaunchURL else { return nil }
        self.pendingLaunchURL = nil
        setResumePrompt(nil)
        return PendingProtectedLaunch(
            url: pendingLaunchURL,
            shouldResumeProtectedSave: shouldResumeProtectedSave
        )
    }

    func dismissResumePrompt() {
        pendingLaunchURL = nil
        setResumePrompt(nil)
    }

    private var canSaveCurrentSession: Bool {
        session.snapshot.emulationState == .running || session.snapshot.emulationState == .paused
    }

    private func completeClose(using intent: CloseGameIntent) async {
        guard var prompt = closePrompt else { return }
        session.persistenceStore.logStore.record("info", "close-game completing intent=\(intent.rawValue)")
        prompt.phase = .closing
        prompt.errorMessage = nil
        setClosePrompt(prompt)

        do {
            session.persistenceStore.logStore.record(
                "info",
                "close-game stop starting intent=\(intent.rawValue)"
            )
            try await session.stop()
            session.persistenceStore.logStore.record(
                "info",
                "close-game stop finished intent=\(intent.rawValue)"
            )
            session.persistenceStore.logStore.record("info", "close-game completed intent=\(intent.rawValue)")
            setClosePrompt(nil)
            onConfirmedExit?(intent)
        } catch {
            prompt.phase = .idle
            prompt.errorMessage = error.localizedDescription
            session.persistenceStore.logStore.record(
                "error",
                "close-game failed intent=\(intent.rawValue) shutdownPhase=\(session.runtimeShutdownPhaseDescription ?? "unknown") error=\(error.localizedDescription)"
            )
            setClosePrompt(prompt)
        }
    }

    private func setClosePrompt(_ prompt: CloseGamePromptState?) {
        closePrompt = prompt
    }

    private func setResumePrompt(_ prompt: ResumeProtectedSavePromptState?) {
        resumePrompt = prompt
    }
}
