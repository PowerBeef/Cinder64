import AppKit
import SwiftUI

@MainActor
@main
struct Cinder64App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: EmulationSession
    @State private var closeGameCoordinator: CloseGameCoordinator
    @State private var mainWindowController = MainWindowController()
    @State private var emulatorDisplayController = EmulatorDisplayController()

    init() {
        do {
            let persistence = try PersistenceStore.live()
            let session = EmulationSession(
                coreHost: Gopher64CoreHost(logStore: persistence.logStore),
                persistenceStore: persistence
            )
            _session = State(initialValue: session)
            _closeGameCoordinator = State(initialValue: CloseGameCoordinator(session: session))
        } catch {
            let fallback = PersistenceStore(
                recentGamesStore: RecentGamesStore(storageURL: FileManager.default.temporaryDirectory.appending(path: "cinder64-fallback-recent.json")),
                saveStateStore: SaveStateMetadataStore(storageURL: FileManager.default.temporaryDirectory.appending(path: "cinder64-fallback-savestates.json"))
            )
            fallback.logStore.record("error", "Failed to build live persistence: \(error.localizedDescription)")
            let session = EmulationSession(
                coreHost: Gopher64CoreHost(logStore: fallback.logStore),
                persistenceStore: fallback
            )
            _session = State(initialValue: session)
            _closeGameCoordinator = State(initialValue: CloseGameCoordinator(session: session))
        }
    }

    var body: some Scene {
        Window("Cinder64", id: "main") {
            ContentView(
                session: session,
                closeGameCoordinator: closeGameCoordinator,
                emulatorDisplayController: emulatorDisplayController,
                openROMRequested: { Task { await openROM() } },
                returnHomeRequested: { closeGameCoordinator.requestCloseGame(.returnHome) },
                completePendingProtectedLaunchRequested: { shouldResumeProtectedSave in
                    Task { await completePendingProtectedLaunch(shouldResumeProtectedSave: shouldResumeProtectedSave) }
                },
                launchROMRequested: { url in
                    LaunchRequestBroker.shared.enqueue(url)
                },
                applyDisplayMode: applyDisplayMode
            )
                .background {
                    MainWindowAccessor(
                        displayMode: MainWindowDisplayMode(settings: session.activeSettings),
                        chromeMode: MainWindowChromeMode(shellMode: ShellPresentation.mode(for: session.snapshot)),
                        controller: mainWindowController
                    )
                }
                .frame(minWidth: 860, minHeight: 560)
                .task {
                    await LaunchRequestBroker.shared.installHandler(handleLaunchRequest)
                    configureCloseGameInterceptors()
                }
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open ROM…") {
                    Task { await openROM() }
                }
                .keyboardShortcut("o")

                Divider()

                Button("Pause") {
                    Task { try? await session.pause() }
                }
                .keyboardShortcut("p")
                .disabled(session.snapshot.emulationState != .running)

                Button("Resume") {
                    Task { try? await session.resume() }
                }
                .keyboardShortcut("r")
                .disabled(session.snapshot.emulationState != .paused)

                Button("Reset") {
                    Task { try? await session.reset() }
                }
                .keyboardShortcut("k")
                .disabled(session.snapshot.emulationState != .running && session.snapshot.emulationState != .paused)
            }

            CommandMenu("Display Mode") {
                ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        applyDisplayMode(mode)
                    }
                    .disabled(MainWindowDisplayMode(settings: session.activeSettings) == mode)
                }
            }
        }

        Settings {
            SettingsView(
                session: session,
                applyDisplayMode: applyDisplayMode
            )
                .frame(width: 460, height: 520)
        }
    }

    private func openROM() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Nintendo 64 ROM to launch in Cinder64."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        LaunchRequestBroker.shared.enqueue(url)
    }

    private func handleLaunchRequest(_ url: URL) async {
        do {
            switch try closeGameCoordinator.prepareLaunchRequest(for: url) {
            case .launchNormally:
                try await launchROM(url: url, loadProtectedCloseSave: false)
            case .promptForProtectedResume:
                reactivateMainWindow()
            }
        } catch {
            session.presentWarning(title: "Unable to Launch ROM", message: error.localizedDescription)
        }
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

    private func applyDisplayMode(_ mode: MainWindowDisplayMode) {
        var settings = session.activeSettings
        mode.apply(to: &settings)
        mainWindowController.apply(mode: mode)

        Task {
            try? await session.updateSettings(settings)
        }
    }

    private func launchROM(url: URL, loadProtectedCloseSave: Bool) async throws {
        try await session.openROM(url: url)
        if loadProtectedCloseSave {
            try await session.loadProtectedCloseState()
        }
        reactivateMainWindow()
        mainWindowController.apply(mode: MainWindowDisplayMode(settings: session.activeSettings))
        startScriptedKeyPlaybackIfNeeded()
    }

    private func completePendingProtectedLaunch(shouldResumeProtectedSave: Bool) async {
        guard let pendingLaunch = closeGameCoordinator.resolvePendingLaunch(
            shouldResumeProtectedSave: shouldResumeProtectedSave
        ) else {
            return
        }

        do {
            try await launchROM(
                url: pendingLaunch.url,
                loadProtectedCloseSave: pendingLaunch.shouldResumeProtectedSave
            )
        } catch {
            session.presentWarning(title: "Unable to Launch ROM", message: error.localizedDescription)
        }
    }

    private func configureCloseGameInterceptors() {
        closeGameCoordinator.onConfirmedExit = { intent in
            switch intent {
            case .returnHome:
                break
            case .closeWindow:
                mainWindowController.closeWindowAfterConfirmedClose()
            case .quitApp:
                Task { @MainActor in
                    do {
                        try await session.dispose()
                    } catch {
                        session.persistenceStore.logStore.record(
                            "warning",
                            "dispose during quit failed: \(error.localizedDescription)"
                        )
                    }
                    appDelegate.continueTerminationAfterConfirmedClose()
                }
            }
        }
        mainWindowController.shouldInterceptWindowClose = {
            closeGameCoordinator.shouldInterceptExitRequests
        }
        mainWindowController.requestCloseGameForWindowClose = {
            closeGameCoordinator.requestCloseGame(.closeWindow)
        }
        mainWindowController.onTrackedWindowWillClose = {
            Task { @MainActor in
                try? await session.dispose()
            }
        }
        appDelegate.shouldInterceptTermination = {
            closeGameCoordinator.shouldInterceptExitRequests
        }
        appDelegate.requestCloseGameForQuit = {
            closeGameCoordinator.requestCloseGame(.quitApp)
        }
        appDelegate.hasTrackedMainWindow = {
            mainWindowController.hasTrackedWindow
        }
        appDelegate.reopenTrackedMainWindow = {
            mainWindowController.reopenTrackedWindowIfNeeded()
        }
    }

    private func startScriptedKeyPlaybackIfNeeded() {
        let broker = LaunchRequestBroker.shared

        if let message = broker.scriptedKeyParseError {
            session.persistenceStore.logStore.record("warning", "scripted-keys ignored: \(message)")
        }

        let steps = broker.scriptedKeySteps
        guard steps.isEmpty == false else { return }
        guard session.snapshot.emulationState == .running else { return }

        let logStore = session.persistenceStore.logStore
        logStore.record("info", "scripted-keys armed count=\(steps.count)")
        let player = ScriptedKeyPlayer(
            steps: steps,
            log: { message in logStore.record("info", message) }
        )

        Task { [player, session] in
            await player.play(on: session)
            logStore.record("info", "scripted-keys playback completed")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var shouldInterceptTermination: (() -> Bool)?
    var requestCloseGameForQuit: (() -> Void)?
    var hasTrackedMainWindow: (() -> Bool)?
    var reopenTrackedMainWindow: (() -> Bool)?
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
            return .terminateNow
        }

        guard shouldInterceptTermination?() == true else {
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
