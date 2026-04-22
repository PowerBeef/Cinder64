import SwiftUI

struct ContentView: View {
    @Bindable var session: EmulationSession
    @Bindable var closeGameCoordinator: CloseGameCoordinator
    let emulatorDisplayController: EmulatorDisplayController
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
                    keyboardInputChanged: session.handleKeyboardInput,
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
    }
}

private struct PromptBackdrop: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.18))
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

private struct PromptOverlayContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            PromptBackdrop()

            content
                .frame(maxWidth: 430)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum ShellPalette {
    static let accent = Color(red: 0.83, green: 0.38, blue: 0.20)
    static let accentSoft = accent.opacity(0.15)
    static let accentGlow = accent.opacity(0.08)
    static let line = Color.white.opacity(0.08)
    static let strongLine = Color.white.opacity(0.12)
    static let stageShadow = Color.black.opacity(0.10)
    static let offBlack = Color(red: 0.04, green: 0.04, blue: 0.05)
}

private struct HomeShellView: View {
    @Bindable var session: EmulationSession
    let isResumePromptVisible: Bool
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void

    var body: some View {
        NavigationSplitView {
            RecentGamesListView(
                session: session,
                openROMRequested: openROMRequested,
                launchROMRequested: launchROMRequested
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let banner = session.snapshot.warningBanner {
                    WarningBannerBar(
                        banner: banner,
                        dismiss: { session.dismissWarningBanner() }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }

                HomeDashboardView(
                    content: HomeDashboardPresentation.content(for: session.recentGames),
                    recentGames: Array(session.recentGames.prefix(3)),
                    openROMRequested: openROMRequested,
                    launchROMRequested: launchROMRequested
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .disabled(isResumePromptVisible)
        .navigationSplitViewStyle(.balanced)
    }
}

private struct HomeDashboardView: View {
    let content: HomeDashboardContent
    let recentGames: [RecentGameRecord]
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topTrailing) {
                HomeCanvasAccent()
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 34) {
                    HomeBrandHeader(
                        content: content,
                        openROMRequested: openROMRequested
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 42) {
                            HomeRecentLaunchBoard(
                                content: content,
                                recentGames: recentGames,
                                openROMRequested: openROMRequested,
                                launchROMRequested: launchROMRequested
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HomeOperationalRail()
                                .frame(width: 250, alignment: .topLeading)
                        }

                        VStack(alignment: .leading, spacing: 28) {
                            HomeRecentLaunchBoard(
                                content: content,
                                recentGames: recentGames,
                                openROMRequested: openROMRequested,
                                launchROMRequested: launchROMRequested
                            )

                            HomeOperationalRail()
                        }
                    }
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct HomeBrandHeader: View {
    let content: HomeDashboardContent
    let openROMRequested: () -> Void

    private let modeItems: [(String, String)] = [
        ("Windowed", "1x, 2x, 3x, 4x"),
        ("Fullscreen", "Available any time"),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 54) {
                heroColumn
                modeRail
            }

            VStack(alignment: .leading, spacing: 24) {
                heroColumn
                modeRail
            }
        }
    }

    private var heroColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(content.title)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .tracking(-1.3)
                .foregroundStyle(.primary)

            Text(content.message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480, alignment: .leading)

            HStack(alignment: .center, spacing: 14) {
                Button(action: openROMRequested) {
                    Label(content.primaryActionTitle, systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ShellPalette.accent)

                Text(content.recentSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modeRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Launch Surface")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            ForEach(modeItems, id: \.0) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(.headline)
                    Text(item.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 18)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ShellPalette.accentSoft)
                .frame(width: 2)
        }
    }
}

private struct HomeCanvasAccent: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(ShellPalette.accentGlow)
                .frame(width: 320, height: 320)
                .offset(x: 210, y: -110)
                .blur(radius: 18)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(ShellPalette.accent.opacity(0.06))
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(18))
                .offset(x: 40, y: 210)
                .blur(radius: 10)
        }
    }
}

private struct HomeRecentLaunchBoard: View {
    let content: HomeDashboardContent
    let recentGames: [RecentGameRecord]
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Launches")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Reopen a familiar session or pick a ROM and let the stage take over.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 16)

            HomePanelDivider()

            if recentGames.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No launches yet. Open a ROM once and it will stay here for the next run.")
                        .foregroundStyle(.secondary)

                    Button(action: openROMRequested) {
                        Label("Choose a ROM", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ShellPalette.accent)
                }
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentGames.enumerated()), id: \.element.identity.id) { index, record in
                        Button {
                            launchROMRequested(record.identity.fileURL)
                        } label: {
                            HomeRecentLaunchRow(record: record, isPrimary: index == 0)
                        }
                        .buttonStyle(.plain)

                        if index < recentGames.count - 1 {
                            HomePanelDivider()
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(ShellPalette.line)
        }
    }
}

private struct HomeRecentLaunchRow: View {
    let record: RecentGameRecord
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPrimary ? ShellPalette.accentSoft.opacity(1.1) : ShellPalette.accentSoft)
                .frame(width: isPrimary ? 40 : 34, height: isPrimary ? 40 : 34)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: isPrimary ? 16 : 14, weight: .semibold))
                        .foregroundStyle(ShellPalette.accent)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.identity.displayName)
                    .font(isPrimary ? .title3.weight(.semibold) : .headline)
                    .lineLimit(1)

                Text(secondaryLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, isPrimary ? 18 : 14)
        .contentShape(Rectangle())
    }

    private var secondaryLabel: String {
        let recency = RecentGameRecencyFormatter.label(for: record.lastOpenedAt)
        if recency == "Today" || recency == "Yesterday" {
            return "\(recency) • \(record.lastOpenedAt.formatted(date: .omitted, time: .shortened))"
        }

        return record.lastOpenedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct HomeOperationalRail: View {
    private let groups: [(String, [(String, String)])] = [
        (
            "Controls",
            [
                ("Start", "Return"),
                ("A Button", "Left Shift"),
                ("Move", "Arrow Keys"),
            ]
        ),
        (
            "Display",
            [
                ("Default", "Fixed window modes"),
                ("Fullscreen", "Available from the display menu"),
            ]
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.0.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(group.1, id: \.0) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.0)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(row.1)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }
}

private struct HomePanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(ShellPalette.line)
            .frame(height: 1)
    }
}

private struct CloseGamePromptCard: View {
    let prompt: CloseGamePromptState
    let cancelRequested: () -> Void
    let closeWithoutSavingRequested: () -> Void
    let saveAndCloseRequested: () -> Void

    private var isBusy: Bool {
        prompt.phase == .saving || prompt.phase == .closing
    }

    private var message: String {
        if let errorMessage = prompt.errorMessage, errorMessage.isEmpty == false {
            return errorMessage
        }

        if prompt.canSave {
            return "Save a protected close-game checkpoint before leaving \(prompt.romDisplayName), or leave without saving."
        }

        return "This session cannot be saved right now, but you can still leave the game or cancel."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Close Game")
                    .font(.title2.weight(.semibold))

                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text(prompt.phase == .saving ? "Saving protected close-game slot…" : "Closing game…")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: cancelRequested)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBusy)

                Spacer(minLength: 0)

                Button("Close Without Saving", action: closeWithoutSavingRequested)
                    .disabled(isBusy)

                Button("Save & Close", action: saveAndCloseRequested)
                    .buttonStyle(.borderedProminent)
                    .tint(ShellPalette.accent)
                    .disabled(prompt.canSave == false || isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 10)
    }
}

private struct ResumeProtectedSavePromptCard: View {
    let prompt: ResumeProtectedSavePromptState
    let continueRequested: () -> Void
    let startFreshRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resume Previous Session?")
                    .font(.title2.weight(.semibold))

                Text("A protected close-game save is available for \(prompt.romDisplayName). Continue from that checkpoint or start a fresh launch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                Button("Start Fresh", action: startFreshRequested)

                Button("Continue", action: continueRequested)
                    .buttonStyle(.borderedProminent)
                    .tint(ShellPalette.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 10)
    }
}

private struct GameplayShellView: View {
    let snapshot: SessionSnapshot
    let displayMode: MainWindowDisplayMode
    let actionAvailability: SessionToolbarActionAvailability
    let isClosePromptVisible: Bool
    let emulatorDisplayController: EmulatorDisplayController
    let returnHomeRequested: () -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void
    let pauseRequested: () -> Void
    let resumeRequested: () -> Void
    let resetRequested: () -> Void
    let saveStateRequested: (Int) -> Void
    let loadStateRequested: (Int) -> Void
    let toggleMuteRequested: () -> Void
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let pumpRuntimeEvents: () -> Void

    @State private var selectedSlot: Int

    init(
        snapshot: SessionSnapshot,
        displayMode: MainWindowDisplayMode,
        actionAvailability: SessionToolbarActionAvailability,
        isClosePromptVisible: Bool,
        emulatorDisplayController: EmulatorDisplayController,
        returnHomeRequested: @escaping () -> Void,
        applyDisplayMode: @escaping (MainWindowDisplayMode) -> Void,
        pauseRequested: @escaping () -> Void,
        resumeRequested: @escaping () -> Void,
        resetRequested: @escaping () -> Void,
        saveStateRequested: @escaping (Int) -> Void,
        loadStateRequested: @escaping (Int) -> Void,
        toggleMuteRequested: @escaping () -> Void,
        surfaceChanged: @escaping (RenderSurfaceDescriptor?) -> Void,
        keyboardInputChanged: @escaping (EmbeddedKeyboardEvent) -> Void,
        pumpRuntimeEvents: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.displayMode = displayMode
        self.actionAvailability = actionAvailability
        self.isClosePromptVisible = isClosePromptVisible
        self.emulatorDisplayController = emulatorDisplayController
        self.returnHomeRequested = returnHomeRequested
        self.applyDisplayMode = applyDisplayMode
        self.pauseRequested = pauseRequested
        self.resumeRequested = resumeRequested
        self.resetRequested = resetRequested
        self.saveStateRequested = saveStateRequested
        self.loadStateRequested = loadStateRequested
        self.toggleMuteRequested = toggleMuteRequested
        self.surfaceChanged = surfaceChanged
        self.keyboardInputChanged = keyboardInputChanged
        self.pumpRuntimeEvents = pumpRuntimeEvents
        _selectedSlot = State(initialValue: snapshot.activeSaveSlot)
    }

    var body: some View {
        ActiveGameplayView(
            snapshot: snapshot,
            displayMode: displayMode,
            emulatorDisplayController: emulatorDisplayController,
            surfaceChanged: surfaceChanged,
            keyboardInputChanged: keyboardInputChanged,
            pumpRuntimeEvents: pumpRuntimeEvents
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
    let emulatorDisplayController: EmulatorDisplayController
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let pumpRuntimeEvents: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let banner = snapshot.warningBanner, snapshot.emulationState == .failed {
                WarningBannerBar(banner: banner)
            }

            RenderSurfaceView(
                snapshot: snapshot,
                controller: emulatorDisplayController,
                surfaceChanged: surfaceChanged,
                keyboardInputChanged: keyboardInputChanged,
                pumpRuntimeEvents: pumpRuntimeEvents
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

struct SessionStatePill: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tintColor)
                .frame(width: 6, height: 6)

            Text(SessionToolbarPresentation.statusTitle(for: snapshot))
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ShellPalette.accentGlow, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tintColor.opacity(0.2))
        }
    }

    private var tintColor: Color {
        switch snapshot.emulationState {
        case .running:
            ShellPalette.accent
        case .paused:
            Color.orange.opacity(0.78)
        case .booting:
            ShellPalette.accent.opacity(0.82)
        case .failed:
            Color.red.opacity(0.82)
        case .stopped:
            .secondary
        }
    }
}

private struct WarningBannerBar: View {
    let banner: WarningBanner
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ShellPalette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(banner.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss warning")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ShellPalette.line)
        }
    }
}

private struct SessionStatusStrip: View {
    let items: [SessionStatusItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SessionStatusInlineItem(item: item)

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(ShellPalette.line)
                            .frame(width: 1, height: 14)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    SessionStatusInlineItem(item: item)
                }
            }
        }
    }
}

private struct SessionStatusInlineItem: View {
    let item: SessionStatusItem

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 11)

            Text(item.label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            Text(item.value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}
