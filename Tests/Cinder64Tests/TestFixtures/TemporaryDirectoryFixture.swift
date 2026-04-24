import Foundation

final class TemporaryDirectoryFixture {
    let directory: URL

    init(prefix: String = "cinder64-tests") throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(_ path: String, directoryHint: URL.DirectoryHint = .notDirectory) -> URL {
        directory.appending(path: path, directoryHint: directoryHint)
    }
}

struct TestWorkspace {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
