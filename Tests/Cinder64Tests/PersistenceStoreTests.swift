import Foundation
import Testing
@testable import Cinder64

struct PersistenceStoreTests {
    @Test func liveUsesTheExplicitAppSupportOverrideEnvironmentVariable() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "cinder64-tests/env-root", directoryHint: .isDirectory)
        let store = try PersistenceStore.live(
            arguments: ["Cinder64"],
            environment: ["CINDER64_APP_SUPPORT_ROOT": root.path]
        )

        #expect(store.directories.root == root)
        #expect(FileManager.default.fileExists(atPath: store.directories.logDirectory.path))
    }

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
