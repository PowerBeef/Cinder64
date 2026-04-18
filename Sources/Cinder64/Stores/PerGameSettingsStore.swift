import Foundation

final class PerGameSettingsStore {
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL) {
        self.storageURL = storageURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadAll() throws -> [String: CoreUserSettings] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return [:]
        }

        return try decoder.decode([String: CoreUserSettings].self, from: Data(contentsOf: storageURL))
    }

    func loadSettings(for identity: ROMIdentity) throws -> CoreUserSettings? {
        try loadAll()[identity.id]
    }

    func saveSettings(_ settings: CoreUserSettings, for identity: ROMIdentity) throws {
        var all = try loadAll()
        all[identity.id] = settings
        try persist(all)
    }

    private func persist(_ settings: [String: CoreUserSettings]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(settings).write(to: storageURL, options: [.atomic])
    }
}
