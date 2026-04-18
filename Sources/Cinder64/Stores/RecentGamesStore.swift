import Foundation

struct RecentGameRecord: Codable, Equatable, Sendable {
    let identity: ROMIdentity
    let lastOpenedAt: Date
}

final class RecentGamesStore {
    private let storageURL: URL
    private let maxItems: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL, maxItems: Int = 20) {
        self.storageURL = storageURL
        self.maxItems = maxItems
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadRecords() throws -> [RecentGameRecord] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return []
        }

        return try decoder.decode([RecentGameRecord].self, from: Data(contentsOf: storageURL))
    }

    func recordLaunch(_ identity: ROMIdentity, openedAt: Date = .now) throws {
        var records = try loadRecords()
        records.removeAll { $0.identity.id == identity.id }
        records.insert(RecentGameRecord(identity: identity, lastOpenedAt: openedAt), at: 0)
        if records.count > maxItems {
            records.removeLast(records.count - maxItems)
        }
        try persist(records)
    }

    private func persist(_ records: [RecentGameRecord]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(records).write(to: storageURL, options: [.atomic])
    }
}
