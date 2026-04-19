import Foundation

enum SaveStateKind: String, Codable, Equatable, Sendable {
    case manual
    case protectedClose
}

struct SaveStateMetadata: Codable, Equatable, Sendable {
    let slot: Int
    let savedAt: Date
    let rendererName: String
    let kind: SaveStateKind

    init(slot: Int, savedAt: Date, rendererName: String, kind: SaveStateKind = .manual) {
        self.slot = slot
        self.savedAt = savedAt
        self.rendererName = rendererName
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case slot
        case savedAt
        case rendererName
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slot = try container.decode(Int.self, forKey: .slot)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        rendererName = try container.decode(String.self, forKey: .rendererName)
        kind = try container.decodeIfPresent(SaveStateKind.self, forKey: .kind) ?? .manual
    }
}

final class SaveStateMetadataStore {
    static let protectedCloseSlot = 9

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

    func recordSaveState(
        for identity: ROMIdentity,
        slot: Int,
        rendererName: String,
        savedAt: Date = .now,
        kind: SaveStateKind = .manual
    ) throws {
        var metadata = try loadMetadata()
        var slots = metadata[identity.id] ?? [:]
        slots[slot] = SaveStateMetadata(
            slot: slot,
            savedAt: savedAt,
            rendererName: rendererName,
            kind: kind
        )
        metadata[identity.id] = slots
        try persist(metadata)
    }

    func protectedCloseSave(for identity: ROMIdentity) throws -> SaveStateMetadata? {
        let metadata = try loadMetadata()
        return metadata[identity.id]?[Self.protectedCloseSlot].flatMap { save in
            save.kind == .protectedClose ? save : nil
        }
    }

    func hasProtectedCloseSave(for identity: ROMIdentity) throws -> Bool {
        try protectedCloseSave(for: identity) != nil
    }

    private func persist(_ metadata: [String: [Int: SaveStateMetadata]]) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(metadata).write(to: storageURL, options: [.atomic])
    }
}
