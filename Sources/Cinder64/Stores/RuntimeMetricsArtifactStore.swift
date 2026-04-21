import Foundation

struct RuntimeMetricsArtifactError: Codable, Equatable, Sendable {
    let message: String
}

struct RuntimeMetricsArtifact: Codable, Equatable, Sendable {
    var startupPhases: [String]
    var shutdownPhases: [String]
    var pumpTickCount: UInt64
    var viCount: UInt64
    var renderFrameCount: UInt64
    var presentCount: UInt64
    var currentFPS: Double
    var lastStructuredError: RuntimeMetricsArtifactError?
    var updatedAt: Date

    static let empty = RuntimeMetricsArtifact(
        startupPhases: [],
        shutdownPhases: [],
        pumpTickCount: 0,
        viCount: 0,
        renderFrameCount: 0,
        presentCount: 0,
        currentFPS: 0,
        lastStructuredError: nil,
        updatedAt: .distantPast
    )
}

final class RuntimeMetricsArtifactStore {
    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    convenience init(logStore: LogStore) {
        let rootDirectory = logStore.logFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.init(fileURL: rootDirectory.appending(path: "metrics.json"))
    }

    func update(_ transform: (inout RuntimeMetricsArtifact) -> Void) {
        var artifact = load() ?? .empty
        transform(&artifact)
        artifact.updatedAt = .now
        persist(artifact)
    }

    private func load() -> RuntimeMetricsArtifact? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(RuntimeMetricsArtifact.self, from: data)
    }

    private func persist(_ artifact: RuntimeMetricsArtifact) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(artifact)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("Cinder64 metrics artifact failure: \(error)\n", stderr)
        }
    }
}
