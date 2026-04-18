import Foundation

struct BundledGopher64RuntimeLocator: Sendable {
    let searchRoots: [URL]

    init(searchRoots: [URL] = BundledGopher64RuntimeLocator.defaultSearchRoots()) {
        self.searchRoots = searchRoots
    }

    func locate() throws -> Gopher64RuntimePaths {
        if let bridgePath = ProcessInfo.processInfo.environment["CINDER64_GOPHER64_BRIDGE"], bridgePath.isEmpty == false {
            let bridgeLibraryURL = URL(fileURLWithPath: bridgePath)
            let supportDirectoryURL = bridgeLibraryURL.deletingLastPathComponent()
            return Gopher64RuntimePaths(
                bridgeLibraryURL: bridgeLibraryURL,
                supportDirectoryURL: supportDirectoryURL,
                moltenVKLibraryURL: Self.findMoltenVK(in: supportDirectoryURL)
            )
        }

        for root in searchRoots {
            let bridgeLibraryURL = root.appending(path: "libcinder64_gopher64.dylib")
            guard FileManager.default.fileExists(atPath: bridgeLibraryURL.path) else {
                continue
            }

            return Gopher64RuntimePaths(
                bridgeLibraryURL: bridgeLibraryURL,
                supportDirectoryURL: root,
                moltenVKLibraryURL: Self.findMoltenVK(in: root)
            )
        }

        throw RuntimeLocatorError.runtimeUnavailable(
            "Cinder64 could not find the bundled gopher64 bridge. Build the Rust bridge and bundle libcinder64_gopher64.dylib with the app, or set CINDER64_GOPHER64_BRIDGE."
        )
    }

    private static func defaultSearchRoots() -> [URL] {
        var roots: [URL] = []

        if let privateFrameworksURL = Bundle.main.privateFrameworksURL {
            roots.append(privateFrameworksURL)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        roots.append(
            currentDirectory
                .appending(path: "ThirdParty", directoryHint: URL.DirectoryHint.isDirectory)
                .appending(path: "gopher64", directoryHint: URL.DirectoryHint.isDirectory)
                .appending(path: "cinder64_bridge", directoryHint: URL.DirectoryHint.isDirectory)
                .appending(path: "target", directoryHint: URL.DirectoryHint.isDirectory)
                .appending(path: "release", directoryHint: URL.DirectoryHint.isDirectory)
        )

        if let executableURL = Bundle.main.executableURL {
            roots.append(executableURL.deletingLastPathComponent())
        }

        return roots
    }

    private static func findMoltenVK(in directory: URL) -> URL? {
        for candidateName in ["libMoltenVK.dylib", "MoltenVK.dylib"] {
            let candidate = directory.appending(path: candidateName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

enum RuntimeLocatorError: LocalizedError {
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message):
            message
        }
    }
}
