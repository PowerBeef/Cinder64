import Foundation

struct SaveStateMetadata: Codable, Equatable, Sendable {
    let slot: Int
    let savedAt: Date
    let rendererName: String
}

final class SaveStateMetadataStore {
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storageURL: URL) {
        self.storageURL = storageURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadMetadata() throws -> [String: [Int: SaveStateMetadata]] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return [:]
        }

        return try decoder.decode([String: [Int: SaveStateMetadata]].self, from: Data(contentsOf: storageURL))
    }

    func recordSaveState(for identity: ROMIdentity, slot: Int, rendererName: String, savedAt: Date = .now) throws {
        var metadata = try loadMetadata()
        var slots = metadata[identity.id] ?? [:]
        slots[slot] = SaveStateMetadata(slot: slot, savedAt: savedAt, rendererName: rendererName)
        metadata[identity.id] = slots
        try persist(metadata)
    }

    private func persist(_ metadata: [String: [Int: SaveStateMetadata]]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(metadata).write(to: storageURL, options: [.atomic])
    }
}
