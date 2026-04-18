import SwiftUI

struct RecentGamesListView: View {
    @Bindable var session: EmulationSession

    var body: some View {
        List {
            Section("Recent Games") {
                if session.recentGames.isEmpty {
                    Text("Open a ROM to populate your recent list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.recentGames, id: \.identity.id) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.identity.displayName)
                            Text(record.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Cinder64")
    }
}
