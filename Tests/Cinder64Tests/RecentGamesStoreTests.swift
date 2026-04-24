import Foundation
import Testing
@testable import Cinder64

@Suite
struct RecentGamesStoreTests {
    @Test func recordsRecentGamesAsAnLRUList() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture()
        let store = RecentGamesStore(storageURL: temporaryDirectory.url("recent-games.json"), maxItems: 2)

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
