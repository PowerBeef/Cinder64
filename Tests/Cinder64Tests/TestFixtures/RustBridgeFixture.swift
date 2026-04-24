import Foundation
@testable import Cinder64

enum RustBridgeFixture {
    struct BuildFailure: Error, CustomStringConvertible {
        let status: Int32

        var description: String {
            "cargo build failed with status \(status)"
        }
    }

    static func buildReleaseBridge() throws -> Gopher64RuntimePaths {
        let manifestURL = TestWorkspace.repositoryRoot
            .appending(path: "ThirdParty", directoryHint: .isDirectory)
            .appending(path: "gopher64", directoryHint: .isDirectory)
            .appending(path: "cinder64_bridge", directoryHint: .isDirectory)
            .appending(path: "Cargo.toml")

        let process = Process()
        process.currentDirectoryURL = TestWorkspace.repositoryRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cargo", "build", "--manifest-path", manifestURL.path, "--release"]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BuildFailure(status: process.terminationStatus)
        }

        let targetDirectory = manifestURL
            .deletingLastPathComponent()
            .appending(path: "target", directoryHint: .isDirectory)
            .appending(path: "release", directoryHint: .isDirectory)

        return Gopher64RuntimePaths(
            bridgeLibraryURL: targetDirectory.appending(path: "libcinder64_gopher64.dylib"),
            supportDirectoryURL: manifestURL.deletingLastPathComponent(),
            moltenVKLibraryURL: nil
        )
    }
}
