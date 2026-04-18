import Foundation

final class LogStore: @unchecked Sendable {
    let logFileURL: URL
    private let formatter: ISO8601DateFormatter

    init(logFileURL: URL) {
        self.logFileURL = logFileURL
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func record(_ level: String, _ message: String) {
        let line = "[\(formatter.string(from: .now))] [\(level)] \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logFileURL.path) == false {
                try Data().write(to: logFileURL)
            }

            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            fputs("Cinder64 log failure: \(error)\n", stderr)
        }
    }
}
