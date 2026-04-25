import SwiftUI

struct ContentView: View {
    @Bindable var frontend: EmulationFrontendModel

    var body: some View {
        Group {
            switch frontend.state.shellMode {
            case .homeDashboard:
                HomeShellView(
                    snapshot: frontend.state.snapshot,
                    recentGames: frontend.state.recentGames,
                    isResumePromptVisible: frontend.state.resumePrompt != nil,
                    openROMRequested: { frontend.send(.chooseROM) },
                    launchROMRequested: { frontend.send(.openROM($0)) },
                    dismissWarningRequested: { frontend.send(.dismissWarning) }
                )
            case .gameplay:
                GameplayShellView(
                    snapshot: frontend.state.snapshot,
                    displayMode: frontend.state.displayMode,
                    actionAvailability: frontend.state.actionAvailability,
                    isClosePromptVisible: frontend.state.closePrompt != nil,
                    renderSurfaceCoordinator: frontend.renderSurfaceCoordinator,
                    returnHomeRequested: { frontend.send(.returnHome) },
                    applyDisplayMode: { frontend.send(.displayModeChanged($0)) },
                    pauseRequested: { frontend.send(.pause) },
                    resumeRequested: { frontend.send(.resume) },
                    resetRequested: { frontend.send(.reset) },
                    saveStateRequested: { frontend.send(.saveState(slot: $0)) },
                    loadStateRequested: { frontend.send(.loadState(slot: $0)) },
                    toggleMuteRequested: { frontend.send(.toggleMute) }
                )
            }
        }
        // The main window no longer hosts the SDL/MoltenVK Metal surface
        // (that moved into a dedicated EmulatorDisplayWindow child), so
        // SwiftUI sheets on the main window composite correctly above any
        // gameplay content and work as expected for modal confirmation.
        .sheet(item: closePromptBinding) { prompt in
            CloseGamePromptCard(
                prompt: prompt,
                cancelRequested: { frontend.send(.cancelCloseGame) },
                closeWithoutSavingRequested: { frontend.send(.closeWithoutSaving) },
                saveAndCloseRequested: { frontend.send(.saveAndClose) }
            )
            .frame(minWidth: 420, idealWidth: 460)
        }
        .sheet(item: resumePromptBinding) { prompt in
            ResumeProtectedSavePromptCard(
                prompt: prompt,
                continueRequested: {
                    frontend.send(.completePendingProtectedLaunch(shouldResumeProtectedSave: true))
                },
                startFreshRequested: {
                    frontend.send(.completePendingProtectedLaunch(shouldResumeProtectedSave: false))
                }
            )
            .frame(minWidth: 420, idealWidth: 460)
        }
        // Hide the emulator child window while any prompt sheet is
        // visible. The child window would otherwise composite above
        // the main window's sheet area and (even with
        // ignoresMouseEvents) cause visual occlusion in that region.
        .onChange(of: frontend.state.isAnyPromptVisible) { _, showingPrompt in
            frontend.send(.promptVisibilityChanged(showingPrompt))
        }
    }

    private var closePromptBinding: Binding<CloseGamePromptState?> {
        Binding(
            get: { frontend.state.closePrompt },
            set: { newValue in
                if newValue == nil {
                    frontend.send(.cancelCloseGame)
                }
            }
        )
    }

    private var resumePromptBinding: Binding<ResumeProtectedSavePromptState?> {
        Binding(
            get: { frontend.state.resumePrompt },
            set: { newValue in
                if newValue == nil {
                    frontend.closeGameCoordinator.dismissResumePrompt()
                }
            }
        )
    }
}
