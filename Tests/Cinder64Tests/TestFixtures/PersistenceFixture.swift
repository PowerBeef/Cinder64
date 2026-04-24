import Foundation
@testable import Cinder64

final class PersistenceFixture {
    let temporaryDirectory: TemporaryDirectoryFixture
    let persistence: PersistenceStore

    let recentGamesURL: URL
    let saveStatesURL: URL
    let settingsURL: URL
    let logURL: URL
    let metricsURL: URL

    init(prefix: String = "cinder64-persistence") throws {
        temporaryDirectory = try TemporaryDirectoryFixture(prefix: prefix)

        let root = temporaryDirectory.url("app-support", directoryHint: .isDirectory)
        let configDirectory = root.appending(path: "config", directoryHint: .isDirectory)
        let dataDirectory = root.appending(path: "data", directoryHint: .isDirectory)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        let logDirectory = root.appending(path: "logs", directoryHint: .isDirectory)

        recentGamesURL = root.appending(path: "recent-games.json")
        saveStatesURL = root.appending(path: "savestate-metadata.json")
        settingsURL = root.appending(path: "per-game-settings.json")
        logURL = logDirectory.appending(path: "runtime.log")
        metricsURL = root.appending(path: "metrics.json")

        persistence = PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: recentGamesURL),
            saveStateStore: SaveStateMetadataStore(storageURL: saveStatesURL),
            settingsStore: PerGameSettingsStore(storageURL: settingsURL),
            directories: AppRuntimeDirectories(
                root: root,
                configDirectory: configDirectory,
                dataDirectory: dataDirectory,
                cacheDirectory: cacheDirectory,
                logDirectory: logDirectory
            ),
            logStore: LogStore(logFileURL: logURL)
        )
    }

    var directory: URL {
        temporaryDirectory.directory
    }

    func logText() throws -> String {
        try String(contentsOf: logURL, encoding: .utf8)
    }
}
