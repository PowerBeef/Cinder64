import Foundation
import Testing
@testable import Cinder64

struct RecentGamesStoreTests {
    @Test func recordsRecentGamesAsAnLRUList() throws {
        let harness = try TemporaryDirectoryHarness()
        let storageURL = harness.directory.appending(path: "recent-games.json")
        let store = RecentGamesStore(storageURL: storageURL, maxItems: 2)

        let gameOne = makeIdentity(name: "Mario")
        let gameTwo = makeIdentity(name: "Zelda")
        let gameThree = makeIdentity(name: "Star Fox")

        try store.recordLaunch(gameOne, openedAt: .init(timeIntervalSince1970: 100))
        try store.recordLaunch(gameTwo, openedAt: .init(timeIntervalSince1970: 200))
        try store.recordLaunch(gameOne, openedAt: .init(timeIntervalSince1970: 300))
        try store.recordLaunch(gameThree, openedAt: .init(timeIntervalSince1970: 400))

        let records = try store.loadRecords()

        #expect(records.map(\.identity.displayName) == ["Star Fox", "Mario"])
        #expect(records.map(\.lastOpenedAt) == [
            .init(timeIntervalSince1970: 400),
            .init(timeIntervalSince1970: 300),
        ])
    }
}

struct TemporaryDirectoryHarness {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
