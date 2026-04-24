import SwiftUI

struct HomeShellView: View {
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
