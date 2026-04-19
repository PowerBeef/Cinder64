import SwiftUI

struct RecentGamesListView: View {
    @Bindable var session: EmulationSession
    let openROMRequested: () -> Void
    let launchROMRequested: (URL) -> Void

    var body: some View {
        List {
            Section {
                SidebarBrandHeader()
                    .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 14, trailing: 10))
                    .listRowBackground(Color.clear)
            }

            Section("Library") {
                Button(action: openROMRequested) {
                    Label("Open ROM…", systemImage: "plus.circle.fill")
                }
            }

            if session.recentGames.isEmpty {
                Section("Recent Launches") {
                    SidebarEmptyState(openROMRequested: openROMRequested)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("Recent Launches") {
                    ForEach(session.recentGames, id: \.identity.id) { record in
                        Button {
                            launchROMRequested(record.identity.fileURL)
                        } label: {
                            RecentGameRow(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cinder64")
    }
}

private struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ShellPalette.accent)
                .frame(width: 8, height: 8)

            Text("Cinder64")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
    }
}

private struct RecentGameRow: View {
    let record: RecentGameRecord

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ShellPalette.accent.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ShellPalette.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.identity.displayName)
                    .lineLimit(1)

                Text(secondaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
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

private struct SidebarEmptyState: View {
    let openROMRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No Recent Launches", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))

            Text("Open a ROM once and it stays here for quick relaunch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: openROMRequested) {
                Label("Open your first ROM", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
