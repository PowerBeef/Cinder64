import Foundation
import Observation

enum EmulationIntent: Equatable, Sendable {
    case chooseROM
    case openROM(URL)
    case returnHome
    case completePendingProtectedLaunch(shouldResumeProtectedSave: Bool)
    case cancelCloseGame
    case closeWithoutSaving
    case saveAndClose
    case dismissWarning
    case pause
    case resume
    case reset
    case saveState(slot: Int)
    case loadState(slot: Int)
    case toggleMute
    case updateSettings(CoreUserSettings)
    case displayModeChanged(MainWindowDisplayMode)
    case renderSurfaceChanged(RenderSurfaceDescriptor?)
    case pumpTick
    case gameplayKey(EmbeddedKeyboardEvent)
    case releaseGameplayInput
    case promptVisibilityChanged(Bool)
}

struct EmulationFrontendState: Equatable, Sendable {
    let snapshot: SessionSnapshot
    let lifecycleState: RuntimeLifecycleState
    let recentGames: [RecentGameRecord]
    let activeSettings: CoreUserSettings
    let inputMapping: InputMappingProfile
    let renderSurface: RenderSurfaceDescriptor?
    let closePrompt: CloseGamePromptState?
    let resumePrompt: ResumeProtectedSavePromptState?
    let displayMode: MainWindowDisplayMode
    let actionAvailability: SessionToolbarActionAvailability
    let shellMode: ShellPresentationMode

    var isAnyPromptVisible: Bool {
        closePrompt != nil || resumePrompt != nil
    }
}

@MainActor
@Observable
final class EmulationFrontendModel {
    let session: EmulationSession
    let closeGameCoordinator: CloseGameCoordinator
    let renderSurfaceCoordinator: RenderSurfaceCoordinator
    let inputCoordinator: GameplayInputCoordinator

    var openROMPanel: () async -> URL?
    var enqueueLaunchRequest: (URL) -> Void
    var reactivateMainWindow: () -> Void
    var applyDisplayModeToWindow: (MainWindowDisplayMode) -> Void
    var startScriptedKeyPlayback: () -> Void
    var onConfirmedExit: (CloseGameIntent) -> Void
    var renderSurfaceWaitTimeout: Duration

    init(
        session: EmulationSession,
        closeGameCoordinator: CloseGameCoordinator,
        renderSurfaceCoordinator: RenderSurfaceCoordinator,
        inputCoordinator: GameplayInputCoordinator = GameplayInputCoordinator(),
        renderSurfaceWaitTimeout: Duration = .seconds(5),
        openROMPanel: @escaping () async -> URL? = { nil },
        enqueueLaunchRequest: @escaping (URL) -> Void = { _ in },
        reactivateMainWindow: @escaping () -> Void = {},
        applyDisplayModeToWindow: @escaping (MainWindowDisplayMode) -> Void = { _ in },
        startScriptedKeyPlayback: @escaping () -> Void = {},
        onConfirmedExit: @escaping (CloseGameIntent) -> Void = { _ in }
    ) {
        self.session = session
        self.closeGameCoordinator = closeGameCoordinator
        self.renderSurfaceCoordinator = renderSurfaceCoordinator
        self.inputCoordinator = inputCoordinator
        self.renderSurfaceWaitTimeout = renderSurfaceWaitTimeout
        self.openROMPanel = openROMPanel
        self.enqueueLaunchRequest = enqueueLaunchRequest
        self.reactivateMainWindow = reactivateMainWindow
        self.applyDisplayModeToWindow = applyDisplayModeToWindow
        self.startScriptedKeyPlayback = startScriptedKeyPlayback
        self.onConfirmedExit = onConfirmedExit

        closeGameCoordinator.onConfirmedExit = { [weak self] intent in
            self?.onConfirmedExit(intent)
        }
    }

    var state: EmulationFrontendState {
        EmulationFrontendState(
            snapshot: session.snapshot,
            lifecycleState: session.lifecycleState,
            recentGames: session.recentGames,
            activeSettings: session.activeSettings,
            inputMapping: session.inputMapping,
            renderSurface: session.renderSurface,
            closePrompt: closeGameCoordinator.closePrompt,
            resumePrompt: closeGameCoordinator.resumePrompt,
            displayMode: MainWindowDisplayMode(settings: session.activeSettings),
            actionAvailability: SessionToolbarPresentation.actionAvailability(for: session.snapshot),
            shellMode: ShellPresentation.mode(for: session.snapshot)
        )
    }

    func send(_ intent: EmulationIntent) {
        Task { @MainActor in
            await handle(intent)
        }
    }

    func handle(_ intent: EmulationIntent) async {
        do {
            try await handleThrowing(intent)
        } catch {
            session.presentWarning(title: warningTitle(for: intent), message: error.localizedDescription)
        }
    }

    private func handleThrowing(_ intent: EmulationIntent) async throws {
        switch intent {
        case .chooseROM:
            guard let url = await openROMPanel() else { return }
            enqueueLaunchRequest(url)
        case let .openROM(url):
            try await prepareAndLaunchROM(url)
        case .returnHome:
            logToolbarIntent("returnHome")
            closeGameCoordinator.requestCloseGame(.returnHome)
        case let .completePendingProtectedLaunch(shouldResumeProtectedSave):
            guard let pendingLaunch = closeGameCoordinator.resolvePendingLaunch(
                shouldResumeProtectedSave: shouldResumeProtectedSave
            ) else {
                return
            }
            try await launchROM(
                url: pendingLaunch.url,
                loadProtectedCloseSave: pendingLaunch.shouldResumeProtectedSave
            )
        case .cancelCloseGame:
            logToolbarIntent("cancelCloseGame")
            closeGameCoordinator.cancelCloseGame()
        case .closeWithoutSaving:
            logToolbarIntent("closeWithoutSaving")
            await closeGameCoordinator.closeWithoutSaving()
        case .saveAndClose:
            logToolbarIntent("saveAndClose")
            await closeGameCoordinator.saveAndClose()
        case .dismissWarning:
            session.dismissWarningBanner()
        case .pause:
            logToolbarIntent("pause")
            try await session.pause()
        case .resume:
            logToolbarIntent("resume")
            try await session.resume()
        case .reset:
            logToolbarIntent("reset")
            try await session.reset()
        case let .saveState(slot):
            logToolbarIntent("saveState slot=\(slot)")
            try await session.saveState(slot: slot)
        case let .loadState(slot):
            logToolbarIntent("loadState slot=\(slot)")
            try await session.loadState(slot: slot)
        case .toggleMute:
            logToolbarIntent("toggleMute")
            var settings = session.activeSettings
            settings.muteAudio.toggle()
            try await session.updateSettings(settings)
        case let .updateSettings(settings):
            try await session.updateSettings(settings)
        case let .displayModeChanged(mode):
            var settings = session.activeSettings
            mode.apply(to: &settings)
            applyDisplayModeToWindow(mode)
            try await session.updateSettings(settings)
        case let .renderSurfaceChanged(descriptor):
            session.updateRenderSurface(descriptor)
        case .pumpTick:
            session.pumpRuntimeEvents()
        case let .gameplayKey(event):
            session.handleKeyboardInput(event)
        case .releaseGameplayInput:
            session.releaseKeyboardInput()
        case let .promptVisibilityChanged(isVisible):
            renderSurfaceCoordinator.setPromptVisible(isVisible)
            inputCoordinator.promptVisibilityDidChange(isVisible: isVisible)
        }
    }

    private func prepareAndLaunchROM(_ url: URL) async throws {
        switch try await closeGameCoordinator.prepareLaunchRequest(for: url) {
        case .launchNormally:
            try await launchROM(url: url, loadProtectedCloseSave: false)
        case .promptForProtectedResume:
            reactivateMainWindow()
        }
    }

    private func launchROM(url: URL, loadProtectedCloseSave: Bool) async throws {
        try await session.openROM(url: url)
        if loadProtectedCloseSave {
            try await session.loadProtectedCloseState()
        }
        reactivateMainWindow()
        applyDisplayModeToWindow(MainWindowDisplayMode(settings: session.activeSettings))
        startScriptedKeyPlayback()
    }

    private func logToolbarIntent(_ message: String) {
        session.persistenceStore.logStore.record(
            "info",
            "frontend toolbar intent \(message) state=\(session.snapshot.emulationState.rawValue)"
        )
    }

    private func warningTitle(for intent: EmulationIntent) -> String {
        switch intent {
        case .openROM, .completePendingProtectedLaunch:
            "Unable to Launch ROM"
        default:
            "Runtime Operation Failed"
        }
    }
}
