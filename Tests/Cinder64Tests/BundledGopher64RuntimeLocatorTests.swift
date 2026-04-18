import Foundation
import Testing
@testable import Cinder64

struct BundledGopher64RuntimeLocatorTests {
    @Test func resolvesABridgeFromAnExplicitSearchRoot() throws {
        let harness = try TemporaryDirectoryHarness()
        let bridgeURL = harness.directory.appending(path: "libcinder64_gopher64.dylib")
        try Data().write(to: bridgeURL)
        let runtimePaths = try BundledGopher64RuntimeLocator(searchRoots: [harness.directory]).locate()

        #expect(runtimePaths.bridgeLibraryURL == bridgeURL)
        #expect(runtimePaths.supportDirectoryURL == harness.directory)
    }

    @Test func throwsWhenNoBridgeCanBeFound() throws {
        let locator = BundledGopher64RuntimeLocator(searchRoots: [URL(filePath: "/tmp/definitely-not-cinder64-runtime", directoryHint: .isDirectory)])

        #expect(throws: RuntimeLocatorError.self) {
            try locator.locate()
        }
    }
}
