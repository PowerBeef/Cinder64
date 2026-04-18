import Foundation
import Testing
@testable import Cinder64

@MainActor
struct Gopher64CoreHostIntegrationTests {
    @Test func invalidROMsFailCleanlyThroughTheBundledBridge() async throws {
        let runtimePaths = try RustBridgeHarness.buildReleaseBridge()
        let harness = try TemporaryDirectoryHarness()
        let logStore = LogStore(logFileURL: harness.directory.appending(path: "runtime.log"))
        let host = Gopher64CoreHost(logStore: logStore)
        let romURL = harness.directory.appending(path: "invalid.z64")
        try Data("definitely-not-a-real-rom".utf8).write(to: romURL)

        let configuration = CoreHostConfiguration(
            romIdentity: try ROMIdentity.make(for: romURL),
            runtimePaths: runtimePaths,
            directories: .preview,
            renderSurface: RenderSurfaceDescriptor(
                windowHandle: 0xCAFEBABE,
                viewHandle: 0xDEADBEEF,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            ),
            settings: .default,
            inputMapping: .standard
        )

        await #expect(throws: Error.self) {
            try await host.openROM(at: romURL, configuration: configuration)
        }
    }

    @Test func zippedROMsFlowThroughTheEmbeddedLoaderPath() async throws {
        let runtimePaths = try RustBridgeHarness.buildReleaseBridge()
        let harness = try TemporaryDirectoryHarness()
        let logStore = LogStore(logFileURL: harness.directory.appending(path: "runtime.log"))
        let host = Gopher64CoreHost(logStore: logStore)

        let romURL = harness.directory.appending(path: "homebrew.z64")
        try Data(validHeaderROMBytes()).write(to: romURL)
        let zipURL = harness.directory.appending(path: "homebrew.zip")
        try zipItem(at: romURL, into: zipURL, from: harness.directory)

        let configuration = CoreHostConfiguration(
            romIdentity: try ROMIdentity.make(for: zipURL),
            runtimePaths: runtimePaths,
            directories: .preview,
            renderSurface: RenderSurfaceDescriptor(
                windowHandle: 0xCAFEBABE,
                viewHandle: 0xDEADBEEF,
                width: 1280,
                height: 720,
                backingScaleFactor: 2
            ),
            settings: .default,
            inputMapping: .standard
        )

        do {
            _ = try await host.openROM(at: zipURL, configuration: configuration)
            Issue.record("The test uses synthetic Cocoa handles, so opening the ROM should fail after loader validation.")
        } catch {
            #expect(error.localizedDescription.contains("supported .z64, .v64, .n64, .zip, or .7z") == false)
            #expect(error.localizedDescription.contains("Video subsystem has not been initialized") == false)
            #expect(error.localizedDescription.contains("Vulkan loader library already loaded") == false)
        }
    }
}

private enum RustBridgeHarness {
    static func buildReleaseBridge() throws -> Gopher64RuntimePaths {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repoRoot
            .appending(path: "ThirdParty", directoryHint: .isDirectory)
            .appending(path: "gopher64", directoryHint: .isDirectory)
            .appending(path: "cinder64_bridge", directoryHint: .isDirectory)
            .appending(path: "Cargo.toml")

        let process = Process()
        process.currentDirectoryURL = repoRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cargo", "build", "--manifest-path", manifestURL.path, "--release"]

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

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

private func validHeaderROMBytes() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4096)
    bytes[0] = 0x80
    bytes[1] = 0x37
    bytes[2] = 0x12
    bytes[3] = 0x40
    return bytes
}

private func zipItem(at sourceURL: URL, into archiveURL: URL, from workingDirectory: URL) throws {
    let process = Process()
    process.currentDirectoryURL = workingDirectory
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-q", archiveURL.lastPathComponent, sourceURL.lastPathComponent]

    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}
