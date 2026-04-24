import Foundation
import Testing
@testable import Cinder64

@MainActor
@Suite(.serialized, .enabled(if: BridgeIntegrationGate.isEnabled))
struct Gopher64CoreHostIntegrationTests {
    @Test func invalidROMsFailCleanlyThroughTheBundledBridge() async throws {
        let runtimePaths = try RustBridgeFixture.buildReleaseBridge()
        let temporaryDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-bridge")
        let logStore = LogStore(logFileURL: temporaryDirectory.url("runtime.log"))
        let host = Gopher64CoreHost(logStore: logStore)
        let romURL = try ROMFixture.writeInvalidROM(named: "invalid.z64", in: temporaryDirectory.directory)

        let configuration = CoreHostConfiguration(
            romIdentity: try ROMIdentity.make(for: romURL),
            runtimePaths: runtimePaths,
            directories: .preview,
            renderSurface: .testSurface(windowHandle: 0xCAFEBABE, viewHandle: 0xDEADBEEF),
            settings: .default,
            inputMapping: .standard
        )

        await #expect(throws: Error.self) {
            try await host.openROM(at: romURL, configuration: configuration)
        }
    }

    @Test func zippedROMsFlowThroughTheEmbeddedLoaderPath() async throws {
        let runtimePaths = try RustBridgeFixture.buildReleaseBridge()
        let temporaryDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-bridge")
        let logStore = LogStore(logFileURL: temporaryDirectory.url("runtime.log"))
        let host = Gopher64CoreHost(logStore: logStore)

        let romURL = try ROMFixture.writeValidHeaderROM(named: "homebrew.z64", in: temporaryDirectory.directory)
        let zipURL = temporaryDirectory.url("homebrew.zip")
        try ROMFixture.zipItem(at: romURL, into: zipURL, from: temporaryDirectory.directory)

        let configuration = CoreHostConfiguration(
            romIdentity: try ROMIdentity.make(for: zipURL),
            runtimePaths: runtimePaths,
            directories: .preview,
            renderSurface: .testSurface(windowHandle: 0xCAFEBABE, viewHandle: 0xDEADBEEF),
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

private enum BridgeIntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CINDER64_RUN_BRIDGE_INTEGRATION"] == "1"
    }
}
