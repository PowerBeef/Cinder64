import SwiftUI

struct ContentView: View {
    @Bindable var session: EmulationSession
    @Bindable var closeGameCoordinator: CloseGameCoordinator
    let emulatorDisplayController: EmulatorDisplayController
    let gameplayKeyboardMonitorCoordinator: GameplayKeyboardMonitorCoordinator
    let openROMRequested: () -> Void
    let returnHomeRequested: () -> Void
    let completePendingProtectedLaunchRequested: (Bool) -> Void
    let launchROMRequested: (URL) -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void

    private var displayMode: MainWindowDisplayMode {
        MainWindowDisplayMode(settings: session.activeSettings)
    }

    private var actionAvailability: SessionToolbarActionAvailability {
        SessionToolbarPresentation.actionAvailability(for: session.snapshot)
    }

    private var shellMode: ShellPresentationMode {
        ShellPresentation.mode(for: session.snapshot)
    }

    var body: some View {
        Group {
            switch shellMode {
            case .homeDashboard:
                HomeShellView(
                    session: session,
                    isResumePromptVisible: closeGameCoordinator.resumePrompt != nil,
                    openROMRequested: openROMRequested,
                    launchROMRequested: launchROMRequested
                )
            case .gameplay:
                GameplayShellView(
                    snapshot: session.snapshot,
                    displayMode: displayMode,
                    actionAvailability: actionAvailability,
                    isClosePromptVisible: closeGameCoordinator.closePrompt != nil,
                    emulatorDisplayController: emulatorDisplayController,
                    returnHomeRequested: returnHomeRequested,
                    applyDisplayMode: applyDisplayMode,
                    pauseRequested: {
                        Task { try? await session.pause() }
                    },
                    resumeRequested: {
                        Task { try? await session.resume() }
                    },
                    resetRequested: {
                        Task { try? await session.reset() }
                    },
                    saveStateRequested: { slot in
                        Task { try? await session.saveState(slot: slot) }
                    },
                    loadStateRequested: { slot in
                        Task { try? await session.loadState(slot: slot) }
                    },
                    toggleMuteRequested: {
                        Task {
                            var settings = session.activeSettings
                            settings.muteAudio.toggle()
                            try? await session.updateSettings(settings)
                        }
                    },
                    surfaceChanged: session.updateRenderSurface,
                    pumpRuntimeEvents: session.pumpRuntimeEvents
                )
            }
        }
        // The main window no longer hosts the SDL/MoltenVK Metal surface
        // (that moved into a dedicated EmulatorDisplayWindow child), so
        // SwiftUI sheets on the main window composite correctly above any
        // gameplay content and work as expected for modal confirmation.
        .sheet(item: $closeGameCoordinator.closePrompt) { prompt in
            CloseGamePromptCard(
                prompt: prompt,
                cancelRequested: closeGameCoordinator.cancelCloseGame,
                closeWithoutSavingRequested: {
                    Task { await closeGameCoordinator.closeWithoutSaving() }
                },
                saveAndCloseRequested: {
                    Task { await closeGameCoordinator.saveAndClose() }
                }
            )
            .frame(minWidth: 420, idealWidth: 460)
        }
        .sheet(item: $closeGameCoordinator.resumePrompt) { prompt in
            ResumeProtectedSavePromptCard(
                prompt: prompt,
                continueRequested: {
                    completePendingProtectedLaunchRequested(true)
                },
                startFreshRequested: {
                    completePendingProtectedLaunchRequested(false)
                }
            )
            .frame(minWidth: 420, idealWidth: 460)
        }
        // Hide the emulator child window while any prompt sheet is
        // visible. The child window would otherwise composite above
        // the main window's sheet area and (even with
        // ignoresMouseEvents) cause visual occlusion in that region.
        .onChange(of: isAnyPromptVisible) { _, showingPrompt in
            emulatorDisplayController.setContentVisible(showingPrompt == false)
            gameplayKeyboardMonitorCoordinator.promptVisibilityDidChange(isVisible: showingPrompt)
        }
    }

    private var isAnyPromptVisible: Bool {
        closeGameCoordinator.closePrompt != nil || closeGameCoordinator.resumePrompt != nil
    }
}
