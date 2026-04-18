import Foundation
import Testing
@testable import Cinder64

struct PersistenceStoreTests {
    @Test func liveUsesTheExplicitAppSupportOverrideArgument() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cinder64-tests/override-root", directoryHint: .isDirectory)
        let store = try PersistenceStore.live(
            arguments: ["Cinder64", "--app-support-root", root.path],
            environment: [:]
        )

        #expect(store.directories.root == root)
        #expect(FileManager.default.fileExists(atPath: store.directories.logDirectory.path))
    }
}
