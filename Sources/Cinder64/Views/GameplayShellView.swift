import SwiftUI

struct GameplayShellView: View {
    let snapshot: SessionSnapshot
    let displayMode: MainWindowDisplayMode
    let actionAvailability: SessionToolbarActionAvailability
    let isClosePromptVisible: Bool
    let renderSurfaceCoordinator: RenderSurfaceCoordinator
    let returnHomeRequested: () -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void
    let pauseRequested: () -> Void
    let resumeRequested: () -> Void
    let resetRequested: () -> Void
    let saveStateRequested: (Int) -> Void
    let loadStateRequested: (Int) -> Void
    let toggleMuteRequested: () -> Void

    @State private var selectedSlot: Int

    init(
        snapshot: SessionSnapshot,
        displayMode: MainWindowDisplayMode,
        actionAvailability: SessionToolbarActionAvailability,
        isClosePromptVisible: Bool,
        renderSurfaceCoordinator: RenderSurfaceCoordinator,
        returnHomeRequested: @escaping () -> Void,
        applyDisplayMode: @escaping (MainWindowDisplayMode) -> Void,
        pauseRequested: @escaping () -> Void,
        resumeRequested: @escaping () -> Void,
        resetRequested: @escaping () -> Void,
        saveStateRequested: @escaping (Int) -> Void,
        loadStateRequested: @escaping (Int) -> Void,
        toggleMuteRequested: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.displayMode = displayMode
        self.actionAvailability = actionAvailability
        self.isClosePromptVisible = isClosePromptVisible
        self.renderSurfaceCoordinator = renderSurfaceCoordinator
        self.returnHomeRequested = returnHomeRequested
        self.applyDisplayMode = applyDisplayMode
        self.pauseRequested = pauseRequested
        self.resumeRequested = resumeRequested
        self.resetRequested = resetRequested
        self.saveStateRequested = saveStateRequested
        self.loadStateRequested = loadStateRequested
        self.toggleMuteRequested = toggleMuteRequested
        _selectedSlot = State(initialValue: snapshot.activeSaveSlot)
    }

    var body: some View {
        ActiveGameplayView(
            snapshot: snapshot,
            displayMode: displayMode,
            renderSurfaceCoordinator: renderSurfaceCoordinator
        )
        .allowsHitTesting(isClosePromptVisible == false)
        .padding(14)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: returnHomeRequested) {
                    GameplayToolbarItemLabel(
                        title: SessionToolbarPresentation.homeActionTitle,
                        systemImage: SessionToolbarPresentation.homeActionSymbolName
                    )
                }
                .disabled(isClosePromptVisible)

                Button(action: transportAction) {
                    GameplayToolbarItemLabel(
                        title: SessionToolbarPresentation.transportTitle(for: snapshot),
                        systemImage: SessionToolbarPresentation.transportSymbolName(for: snapshot)
                    )
                }
                .disabled(isClosePromptVisible || (actionAvailability.canPause == false && actionAvailability.canResume == false))

                Button(action: resetRequested) {
                    GameplayToolbarItemLabel(title: "Reset", systemImage: "arrow.clockwise")
                }
                .disabled(isClosePromptVisible || actionAvailability.canReset == false)

                Menu {
                    Button("Save to Slot \(selectedSlot + 1)") {
                        saveStateRequested(selectedSlot)
                    }

                    Button("Load Slot \(selectedSlot + 1)") {
                        loadStateRequested(selectedSlot)
                    }

                    Divider()

                    ForEach(0 ..< 4, id: \.self) { slot in
                        Button("Use Slot \(slot + 1)") {
                            selectedSlot = slot
                        }
                    }
                } label: {
                    GameplayToolbarItemLabel(
                        title: SessionToolbarPresentation.stateMenuTitle(forSlot: selectedSlot),
                        systemImage: "square.stack.3d.down.right"
                    )
                }
                .disabled(isClosePromptVisible || actionAvailability.canUseStateMenu == false)
            }

            ToolbarItem(placement: .principal) {
                GameplayTitlebarTitle(snapshot: snapshot)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: toggleMuteRequested) {
                    GameplayToolbarItemLabel(
                        title: SessionToolbarPresentation.audioToolTitle(for: snapshot),
                        systemImage: SessionToolbarPresentation.audioToolSymbolName(for: snapshot)
                    )
                }
                .disabled(isClosePromptVisible || actionAvailability.canToggleAudio == false)

                Menu {
                    ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                        Button(mode.title) {
                            applyDisplayMode(mode)
                        }
                        .disabled(displayMode == mode)
                    }
                } label: {
                    GameplayToolbarItemLabel(
                        title: SessionToolbarPresentation.compactDisplayTitle(for: displayMode),
                        systemImage: "display"
                    )
                }
                .disabled(isClosePromptVisible)
            }
        }
        .onChange(of: snapshot.activeSaveSlot) { _, newValue in
            selectedSlot = newValue
        }
    }

    private func transportAction() {
        if snapshot.emulationState == .paused {
            resumeRequested()
        } else {
            pauseRequested()
        }
    }
}

private struct ActiveGameplayView: View {
    let snapshot: SessionSnapshot
    let displayMode: MainWindowDisplayMode
    let renderSurfaceCoordinator: RenderSurfaceCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let banner = snapshot.warningBanner, snapshot.emulationState == .failed {
                WarningBannerBar(banner: banner)
            }

            RenderSurfaceView(
                snapshot: snapshot,
                coordinator: renderSurfaceCoordinator
            )

            SessionStatusStrip(
                items: SessionStatusStripPresentation.items(
                    for: snapshot,
                    displayMode: displayMode
                )
            )
        }
    }
}

private struct GameplayTitlebarTitle: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Text(SessionToolbarPresentation.title(for: snapshot))
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            SessionStatePill(snapshot: snapshot)
        }
        .frame(maxWidth: 320)
    }
}

private struct GameplayToolbarItemLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}
