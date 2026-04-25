import AppKit
import SwiftUI

@MainActor
@main
struct Cinder64App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var frontend: EmulationFrontendModel
    @State private var mainWindowController = MainWindowController()

    init() {
        do {
            let persistence = try PersistenceStore.live()
            _frontend = State(initialValue: Self.makeFrontend(persistence: persistence))
        } catch {
            let fallback = PersistenceStore(
                recentGamesStore: RecentGamesStore(storageURL: FileManager.default.temporaryDirectory.appending(path: "cinder64-fallback-recent.json")),
                saveStateStore: SaveStateMetadataStore(storageURL: FileManager.default.temporaryDirectory.appending(path: "cinder64-fallback-savestates.json"))
            )
            fallback.logStore.record("error", "Failed to build live persistence: \(error.localizedDescription)")
            _frontend = State(initialValue: Self.makeFrontend(persistence: fallback))
        }
    }

    var body: some Scene {
        Window("Cinder64", id: "main") {
            ContentView(frontend: frontend)
                .background {
                    MainWindowAccessor(
                        displayMode: frontend.state.displayMode,
                        chromeMode: MainWindowChromeMode(shellMode: frontend.state.shellMode),
                        controller: mainWindowController
                    )
                }
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    configureFrontendIntegration()
                    await LaunchRequestBroker.shared.installHandler { url in
                        await frontend.handle(.openROM(url))
                    }
                }
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open ROM…") {
                    frontend.send(.chooseROM)
                }
                .keyboardShortcut("o")

                Divider()

                Button("Pause") {
                    frontend.send(.pause)
                }
                .keyboardShortcut("p")
                .disabled(frontend.state.snapshot.emulationState != .running)

                Button("Resume") {
                    frontend.send(.resume)
                }
                .keyboardShortcut("r")
                .disabled(frontend.state.snapshot.emulationState != .paused)

                Button("Reset") {
                    frontend.send(.reset)
                }
                .keyboardShortcut("k")
                .disabled(frontend.state.snapshot.emulationState != .running && frontend.state.snapshot.emulationState != .paused)
            }

            CommandMenu("Display Mode") {
                ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        frontend.send(.displayModeChanged(mode))
                    }
                    .disabled(frontend.state.displayMode == mode)
                }
            }
        }

        Settings {
            SettingsView(frontend: frontend)
                .frame(width: 460, height: 520)
        }
    }

    private static func makeFrontend(persistence: PersistenceStore) -> EmulationFrontendModel {
        let session = EmulationSession(
            coreHost: makeLiveRuntimeCoreHost(logStore: persistence.logStore),
            persistenceStore: persistence
        )
        let closeGameCoordinator = CloseGameCoordinator(session: session)
        let renderSurfaceCoordinator = RenderSurfaceCoordinator(
            displayController: EmulatorDisplayController()
        )
        return EmulationFrontendModel(
            session: session,
            closeGameCoordinator: closeGameCoordinator,
            renderSurfaceCoordinator: renderSurfaceCoordinator,
            inputCoordinator: GameplayInputCoordinator()
        )
    }

    private func chooseROMFromPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Nintendo 64 ROM to launch in Cinder64."

        return panel.runModal() == .OK ? panel.url : nil
    }

    private func reactivateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let candidateWindow = NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: \.isVisible)
            ?? NSApp.windows.first
        candidateWindow?.makeKeyAndOrderFront(nil)
        if let candidateWindow {
            mainWindowController.bind(window: candidateWindow)
        }
    }

    private func configureFrontendIntegration() {
        frontend.openROMPanel = chooseROMFromPanel
        frontend.enqueueLaunchRequest = { url in
            LaunchRequestBroker.shared.enqueue(url)
        }
        frontend.reactivateMainWindow = reactivateMainWindow
        frontend.applyDisplayModeToWindow = { mode in
            mainWindowController.apply(mode: mode)
        }
        frontend.startScriptedKeyPlayback = startScriptedKeyPlaybackIfNeeded
        frontend.onConfirmedExit = { intent in
            switch intent {
            case .returnHome:
                break
            case .closeWindow:
                mainWindowController.closeWindowAfterConfirmedClose()
            case .quitApp:
                Task { @MainActor in
                    do {
                        try await frontend.session.dispose()
                    } catch {
                        frontend.session.persistenceStore.logStore.record(
                            "warning",
                            "dispose during quit failed: \(error.localizedDescription)"
                        )
                    }
                    appDelegate.continueTerminationAfterConfirmedClose()
                }
            }
        }
        frontend.renderSurfaceCoordinator.onSurfaceChanged = { descriptor in
            frontend.send(.renderSurfaceChanged(descriptor))
        }
        frontend.renderSurfaceCoordinator.onPumpTick = {
            frontend.send(.pumpTick)
        }
        mainWindowController.shouldInterceptWindowClose = {
            frontend.closeGameCoordinator.shouldInterceptExitRequests
        }
        mainWindowController.requestCloseGameForWindowClose = {
            frontend.closeGameCoordinator.requestCloseGame(.closeWindow)
        }
        mainWindowController.onTrackedWindowWillClose = {
            frontend.inputCoordinator.updateTrackedWindow(nil)
            Task { @MainActor in
                try? await frontend.session.dispose()
            }
        }
        mainWindowController.onTrackedWindowChanged = { window in
            frontend.inputCoordinator.updateTrackedWindow(window)
        }
        appDelegate.shouldInterceptTermination = {
            frontend.closeGameCoordinator.shouldInterceptExitRequests
        }
        appDelegate.requestCloseGameForQuit = {
            frontend.closeGameCoordinator.requestCloseGame(.quitApp)
        }
        appDelegate.hasTrackedMainWindow = {
            mainWindowController.hasTrackedWindow
        }
        appDelegate.reopenTrackedMainWindow = {
            mainWindowController.reopenTrackedWindowIfNeeded()
        }
        appDelegate.applicationWillTerminate = {
            frontend.inputCoordinator.remove()
        }
        frontend.inputCoordinator.install(
            eventHandler: { event in
                frontend.send(.gameplayKey(event))
            },
            releaseHeldInput: {
                frontend.send(.releaseGameplayInput)
            },
            emulationState: {
                frontend.state.snapshot.emulationState
            },
            hasVisiblePrompt: {
                frontend.state.isAnyPromptVisible
            }
        )
    }

    private func startScriptedKeyPlaybackIfNeeded() {
        let broker = LaunchRequestBroker.shared

        if let message = broker.scriptedKeyParseError {
            frontend.session.persistenceStore.logStore.record("warning", "scripted-keys ignored: \(message)")
        }

        let steps = broker.scriptedKeySteps
        guard steps.isEmpty == false else { return }
        guard frontend.state.snapshot.emulationState == .running else { return }

        let logStore = frontend.session.persistenceStore.logStore
        logStore.record("info", "scripted-keys armed count=\(steps.count)")
        let player = ScriptedKeyPlayer(
            steps: steps,
            log: { message in logStore.record("info", message) }
        )

        Task { [player, frontend] in
            await player.play(on: frontend.session)
            logStore.record("info", "scripted-keys playback completed")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var shouldInterceptTermination: (() -> Bool)?
    var requestCloseGameForQuit: (() -> Void)?
    var hasTrackedMainWindow: (() -> Bool)?
    var reopenTrackedMainWindow: (() -> Bool)?
    var applicationWillTerminate: (() -> Void)?
    private var allowsTerminationAfterConfirmedClose = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.isEmpty == false else {
            return
        }

        for url in urls {
            LaunchRequestBroker.shared.enqueue(url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        LaunchRequestBroker.shared.enqueue(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard filenames.isEmpty == false else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        for filename in filenames {
            LaunchRequestBroker.shared.enqueue(URL(fileURLWithPath: filename))
        }

        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let action = AppReopenPresentation.action(
            hasVisibleWindows: flag,
            hasTrackedMainWindow: hasTrackedMainWindow?() == true
        )

        switch action {
        case .keepCurrentWindowState:
            return true
        case .showTrackedWindow:
            _ = reopenTrackedMainWindow?()
            return false
        case .allowSystemWindowReopen:
            return true
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowsTerminationAfterConfirmedClose {
            allowsTerminationAfterConfirmedClose = false
            applicationWillTerminate?()
            return .terminateNow
        }

        guard shouldInterceptTermination?() == true else {
            applicationWillTerminate?()
            return .terminateNow
        }

        requestCloseGameForQuit?()
        return .terminateCancel
    }

    @MainActor
    func continueTerminationAfterConfirmedClose() {
        allowsTerminationAfterConfirmedClose = true
        NSApp.terminate(nil)
    }
}
