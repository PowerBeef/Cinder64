import Foundation

struct PersistenceStore {
    let recentGamesStore: RecentGamesStore
    let saveStateStore: SaveStateMetadataStore
    let settingsStore: PerGameSettingsStore
    let directories: AppRuntimeDirectories
    let logStore: LogStore

    init(
        recentGamesStore: RecentGamesStore,
        saveStateStore: SaveStateMetadataStore,
        settingsStore: PerGameSettingsStore = PerGameSettingsStore(storageURL: FileManager.default.temporaryDirectory.appending(path: "cinder64-settings.json")),
        directories: AppRuntimeDirectories = .preview,
        logStore: LogStore = LogStore(logFileURL: FileManager.default.temporaryDirectory.appending(path: "cinder64.log"))
    ) {
        self.recentGamesStore = recentGamesStore
        self.saveStateStore = saveStateStore
        self.settingsStore = settingsStore
        self.directories = directories
        self.logStore = logStore
    }

    static func live(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PersistenceStore {
        let appSupport = try resolveRootDirectory(arguments: arguments, environment: environment)
        let directories = AppRuntimeDirectories(
            root: appSupport,
            configDirectory: appSupport.appending(path: "config", directoryHint: .isDirectory),
            dataDirectory: appSupport.appending(path: "data", directoryHint: .isDirectory),
            cacheDirectory: appSupport.appending(path: "cache", directoryHint: .isDirectory),
            logDirectory: appSupport.appending(path: "logs", directoryHint: .isDirectory)
        )

        for directory in [
            directories.root,
            directories.configDirectory,
            directories.dataDirectory,
            directories.cacheDirectory,
            directories.logDirectory,
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return PersistenceStore(
            recentGamesStore: RecentGamesStore(storageURL: directories.root.appending(path: "recent-games.json")),
            saveStateStore: SaveStateMetadataStore(storageURL: directories.root.appending(path: "savestate-metadata.json")),
            settingsStore: PerGameSettingsStore(storageURL: directories.root.appending(path: "per-game-settings.json")),
            directories: directories,
            logStore: LogStore(logFileURL: directories.logDirectory.appending(path: "runtime.log"))
        )
    }

    private static func resolveRootDirectory(
        arguments: [String],
        environment: [String: String]
    ) throws -> URL {
        if let overridePath = environment["CINDER64_APP_SUPPORT_ROOT"], overridePath.isEmpty == false {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }

        if let overrideIndex = arguments.firstIndex(of: "--app-support-root") {
            let nextIndex = arguments.index(after: overrideIndex)

            if arguments.indices.contains(nextIndex) {
                return URL(fileURLWithPath: arguments[nextIndex], isDirectory: true)
            }
        }

        return try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Cinder64", directoryHint: .isDirectory)
    }
}

extension AppRuntimeDirectories {
    static let preview = AppRuntimeDirectories(
        root: FileManager.default.temporaryDirectory.appending(path: "cinder64-preview", directoryHint: .isDirectory),
        configDirectory: FileManager.default.temporaryDirectory.appending(path: "cinder64-preview/config", directoryHint: .isDirectory),
        dataDirectory: FileManager.default.temporaryDirectory.appending(path: "cinder64-preview/data", directoryHint: .isDirectory),
        cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "cinder64-preview/cache", directoryHint: .isDirectory),
        logDirectory: FileManager.default.temporaryDirectory.appending(path: "cinder64-preview/logs", directoryHint: .isDirectory)
    )
}
