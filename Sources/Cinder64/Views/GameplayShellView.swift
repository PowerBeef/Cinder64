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
    @State private var isStatePopoverPresented = false
    @State private var isDisplayPopoverPresented = false

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
        ZStack(alignment: .topTrailing) {
            ActiveGameplayView(
                snapshot: snapshot,
                displayMode: displayMode,
                renderSurfaceCoordinator: renderSurfaceCoordinator
            )

            if isStatePopoverPresented {
                GameplayStatePopoverContent(
                    selectedSlot: $selectedSlot,
                    saveStateRequested: { slot in
                        closeToolbarPopovers()
                        saveStateRequested(slot)
                    },
                    loadStateRequested: { slot in
                        closeToolbarPopovers()
                        loadStateRequested(slot)
                    }
                )
                .padding(.top, 12)
                .padding(.trailing, 132)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                .zIndex(2)
            }

            if isDisplayPopoverPresented {
                GameplayDisplayPopoverContent(
                    displayMode: displayMode,
                    applyDisplayMode: { mode in
                        closeToolbarPopovers()
                        applyDisplayMode(mode)
                    }
                )
                .padding(.top, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                .zIndex(2)
            }
        }
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

                Button {
                    setToolbarPopoverVisibility(
                        state: isStatePopoverPresented == false,
                        display: false
                    )
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

                Button {
                    setToolbarPopoverVisibility(
                        state: false,
                        display: isDisplayPopoverPresented == false
                    )
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
        .onChange(of: isClosePromptVisible) { _, isVisible in
            if isVisible {
                closeToolbarPopovers()
            }
        }
    }

    private func transportAction() {
        if snapshot.emulationState == .paused {
            resumeRequested()
        } else {
            pauseRequested()
        }
    }

    private func closeToolbarPopovers() {
        setToolbarPopoverVisibility(state: false, display: false)
    }

    private func setToolbarPopoverVisibility(state: Bool, display: Bool) {
        isStatePopoverPresented = state
        isDisplayPopoverPresented = display
        renderSurfaceCoordinator.setPromptVisible(state || display || isClosePromptVisible)
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

private struct GameplayStatePopoverContent: View {
    @Binding var selectedSlot: Int
    let saveStateRequested: (Int) -> Void
    let loadStateRequested: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State")
                .font(.headline.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(0 ..< 4, id: \.self) { slot in
                    Button("Slot \(slot + 1)") {
                        selectedSlot = slot
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(slot == selectedSlot ? ShellPalette.accent : Color.secondary.opacity(0.35))
                }
            }

            Divider()

            Button {
                saveStateRequested(selectedSlot)
            } label: {
                Label("Save to Slot \(selectedSlot + 1)", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .tint(ShellPalette.accent)

            Button {
                loadStateRequested(selectedSlot)
            } label: {
                Label("Load Slot \(selectedSlot + 1)", systemImage: "arrow.down.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 250)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }
}

private struct GameplayDisplayPopoverContent: View {
    let displayMode: MainWindowDisplayMode
    let applyDisplayMode: (MainWindowDisplayMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display")
                .font(.headline.weight(.semibold))

            ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                Button {
                    applyDisplayMode(mode)
                } label: {
                    Label(
                        mode.title,
                        systemImage: displayMode == mode ? "checkmark" : "display"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(displayMode == mode)
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }
}
