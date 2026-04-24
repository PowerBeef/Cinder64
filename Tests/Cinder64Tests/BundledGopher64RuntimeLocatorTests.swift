import Foundation
import Testing
@testable import Cinder64

@Suite
struct BundledGopher64RuntimeLocatorTests {
    @Test func resolvesABridgeFromAnExplicitSearchRoot() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture()
        let bridgeURL = temporaryDirectory.url("libcinder64_gopher64.dylib")
        try Data().write(to: bridgeURL)

        let runtimePaths = try BundledGopher64RuntimeLocator(searchRoots: [temporaryDirectory.directory]).locate()

        #expect(runtimePaths.bridgeLibraryURL == bridgeURL)
        #expect(runtimePaths.supportDirectoryURL == temporaryDirectory.directory)
    }

    @Test func throwsWhenNoBridgeCanBeFound() throws {
        let locator = BundledGopher64RuntimeLocator(
            searchRoots: [URL(filePath: "/tmp/definitely-not-cinder64-runtime", directoryHint: .isDirectory)]
        )

        #expect(throws: RuntimeLocatorError.self) {
            try locator.locate()
        }
    }
}
