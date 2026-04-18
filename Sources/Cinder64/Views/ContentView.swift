import SwiftUI

struct ContentView: View {
    @Bindable var session: EmulationSession
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void

    private var displayMode: MainWindowDisplayMode {
        MainWindowDisplayMode(settings: session.activeSettings)
    }

    private var actionAvailability: SessionToolbarActionAvailability {
        SessionToolbarPresentation.actionAvailability(for: session.snapshot)
    }

    var body: some View {
        NavigationSplitView {
            RecentGamesListView(
                session: session,
                openROMRequested: openROMRequested,
                launchROMRequested: launchROMRequested
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            Group {
                switch ShellPresentation.mode(for: session.snapshot) {
                case .homeDashboard:
                    HomeDashboardView(
                        content: HomeDashboardPresentation.content(for: session.recentGames),
                        recentGames: Array(session.recentGames.prefix(3)),
                        openROMRequested: openROMRequested,
                        launchROMRequested: launchROMRequested
                    )
                case .gameplay:
                    ActiveGameplayView(
                        snapshot: session.snapshot,
                        displayMode: displayMode,
                        actionAvailability: actionAvailability,
                        openROMRequested: openROMRequested,
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
                        surfaceChanged: session.updateRenderSurface,
                        keyboardInputChanged: session.handleKeyboardInput,
                        pumpRuntimeEvents: session.pumpRuntimeEvents
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

enum ShellPalette {
    static let accent = Color(red: 0.91, green: 0.42, blue: 0.20)
    static let accentSoft = accent.opacity(0.16)
    static let line = Color.white.opacity(0.08)
    static let strongLine = Color.white.opacity(0.12)
    static let stageShadow = Color.black.opacity(0.12)
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

                VStack(alignment: .leading, spacing: 24) {
                    HomeBrandHeader(
                        content: content,
                        openROMRequested: openROMRequested
                    )

                    HomePanelDivider()

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 32) {
                            HomeRecentLaunchColumn(
                                content: content,
                                recentGames: recentGames,
                                openROMRequested: openROMRequested,
                                launchROMRequested: launchROMRequested
                            )

                            HomeOperationsColumn()
                                .frame(width: 260, alignment: .topLeading)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            HomeRecentLaunchColumn(
                                content: content,
                                recentGames: recentGames,
                                openROMRequested: openROMRequested,
                                launchROMRequested: launchROMRequested
                            )

                            HomeOperationsColumn()
                        }
                    }

                    HomePanelDivider()

                    HomeUtilityStrip()
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(ShellPalette.line)
            }
        }
    }
}

private struct HomeBrandHeader: View {
    let content: HomeDashboardContent
    let openROMRequested: () -> Void

    private let readinessItems: [(String, String)] = [
        ("Windowed", "1x, 2x, 3x, 4x"),
        ("Display", "Fullscreen available"),
        ("Input", "Keyboard ready on launch"),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) {
                heroCopy
                Spacer(minLength: 0)
                readinessAside
            }

            VStack(alignment: .leading, spacing: 20) {
                heroCopy
                readinessAside
            }
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            Text(content.title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(content.message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

            HStack(alignment: .center, spacing: 12) {
                Button(action: openROMRequested) {
                    Label(content.primaryActionTitle, systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ShellPalette.accent)

                Text(content.recentSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readinessAside: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to Play")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(readinessItems, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.1)
                            .font(.subheadline)
                    }
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
        ZStack {
            Circle()
                .fill(ShellPalette.accent.opacity(0.22))
                .frame(width: 260, height: 260)
                .offset(x: 170, y: -120)
                .blur(radius: 16)

            Circle()
                .fill(ShellPalette.accent.opacity(0.10))
                .frame(width: 200, height: 200)
                .offset(x: 30, y: 40)
                .blur(radius: 28)
        }
        .clipped()
    }
}

private struct HomeRecentLaunchColumn: View {
    let content: HomeDashboardContent
    let recentGames: [RecentGameRecord]
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Launches")
                .font(.headline)

            if recentGames.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your recent library appears here after the first successful launch.")
                        .foregroundStyle(.secondary)

                    Button(action: openROMRequested) {
                        Label("Choose a ROM", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentGames.enumerated()), id: \.element.identity.id) { index, record in
                        Button {
                            launchROMRequested(record.identity.fileURL)
                        } label: {
                            HomeRecentLaunchRow(record: record)
                        }
                        .buttonStyle(.plain)

                        if index < recentGames.count - 1 {
                            HomePanelDivider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeRecentLaunchRow: View {
    let record: RecentGameRecord

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ShellPalette.accentSoft)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ShellPalette.accent)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.identity.displayName)
                    .font(.headline)
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
        }
        .padding(.vertical, 12)
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

private struct HomeOperationsColumn: View {
    private let controlRows: [(String, String)] = [
        ("Start", "Return"),
        ("A Button", "Left Shift"),
        ("Move", "Arrow Keys"),
    ]

    private let modeRows: [(String, String)] = [
        ("Windowed", "1x • 2x • 3x • 4x"),
        ("Fullscreen", "Available from the display menu"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HomeInfoGroup(
                title: "Default Controls",
                rows: controlRows
            )

            HomeInfoGroup(
                title: "Display Modes",
                rows: modeRows
            )
        }
    }
}

private struct HomeInfoGroup: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(row.1)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}

private struct HomeUtilityStrip: View {
    private let items: [(String, String)] = [
        ("Workspace", "Gameplay takes over this canvas once a ROM boots."),
        ("Sidebar", "Recent launches stay pinned for quick relaunch."),
        ("Settings", "Display, audio, and speed stay out of the way."),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(items, id: \.0) { item in
                    HomeUtilityFact(title: item.0, value: item.1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(items, id: \.0) { item in
                    HomeUtilityFact(title: item.0, value: item.1)
                }
            }
        }
    }
}

private struct HomeUtilityFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HomePanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(ShellPalette.line)
            .frame(height: 1)
    }
}

private struct ActiveGameplayView: View {
    let snapshot: SessionSnapshot
    let displayMode: MainWindowDisplayMode
    let actionAvailability: SessionToolbarActionAvailability
    let openROMRequested: () -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void
    let pauseRequested: () -> Void
    let resumeRequested: () -> Void
    let resetRequested: () -> Void
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let pumpRuntimeEvents: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SlimGameplayHeader(
                snapshot: snapshot,
                displayMode: displayMode,
                actionAvailability: actionAvailability,
                openROMRequested: openROMRequested,
                applyDisplayMode: applyDisplayMode,
                pauseRequested: pauseRequested,
                resumeRequested: resumeRequested,
                resetRequested: resetRequested
            )

            if let banner = snapshot.warningBanner, snapshot.emulationState == .failed {
                WarningBannerBar(banner: banner)
            }

            RenderSurfaceView(
                snapshot: snapshot,
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

            Spacer(minLength: 0)
        }
    }
}

private struct SlimGameplayHeader: View {
    let snapshot: SessionSnapshot
    let displayMode: MainWindowDisplayMode
    let actionAvailability: SessionToolbarActionAvailability
    let openROMRequested: () -> Void
    let applyDisplayMode: (MainWindowDisplayMode) -> Void
    let pauseRequested: () -> Void
    let resumeRequested: () -> Void
    let resetRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    titleBlock
                    Spacer(minLength: 12)
                    actionRow
                }

                VStack(alignment: .leading, spacing: 12) {
                    titleBlock
                    actionRow
                }
            }

            HomePanelDivider()
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(SessionToolbarPresentation.title(for: snapshot))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                SessionStatePill(snapshot: snapshot)
            }

            if let subtitle = SessionToolbarPresentation.subtitle(for: snapshot) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: openROMRequested) {
                Label("Open ROM", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(ShellPalette.accent)

            Button(action: transportAction) {
                Label(
                    SessionToolbarPresentation.transportTitle(for: snapshot),
                    systemImage: SessionToolbarPresentation.transportSymbolName(for: snapshot)
                )
            }
            .buttonStyle(.bordered)
            .disabled(actionAvailability.canPause == false && actionAvailability.canResume == false)

            Button(action: resetRequested) {
                Label("Reset", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(actionAvailability.canReset == false)

            Spacer(minLength: 4)

            Menu {
                ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        applyDisplayMode(mode)
                    }
                    .disabled(displayMode == mode)
                }
            } label: {
                Label(displayMode.title, systemImage: "display")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .controlSize(.small)
    }

    private func transportAction() {
        if snapshot.emulationState == .paused {
            resumeRequested()
        } else {
            pauseRequested()
        }
    }
}

struct SessionStatePill: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tintColor)
                .frame(width: 7, height: 7)

            Text(SessionToolbarPresentation.statusTitle(for: snapshot))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tintColor.opacity(0.22))
        }
    }

    private var tintColor: Color {
        switch snapshot.emulationState {
        case .running:
            .green
        case .paused:
            .orange
        case .booting:
            ShellPalette.accent
        case .failed:
            .red
        case .stopped:
            .secondary
        }
    }
}

private struct WarningBannerBar: View {
    let banner: WarningBanner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                Text(banner.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.24))
                .frame(height: 1)
        }
    }
}

private struct SessionStatusStrip: View {
    let items: [SessionStatusItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SessionStatusInlineItem(item: item)

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(ShellPalette.line)
                            .frame(width: 1, height: 20)
                    }
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
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
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(item.value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }
}
