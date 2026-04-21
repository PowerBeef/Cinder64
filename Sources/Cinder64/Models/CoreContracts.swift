import Foundation

struct CoreUserSettings: Codable, Equatable, Sendable {
    var startFullscreen: Bool
    var windowScale: Int
    var muteAudio: Bool
    var speedPercent: Int
    var upscaleMultiplier: Int
    var integerScaling: Bool
    var crtFilterEnabled: Bool

    static let `default` = CoreUserSettings(
        startFullscreen: false,
        windowScale: 1,
        muteAudio: false,
        speedPercent: 100,
        upscaleMultiplier: 2,
        integerScaling: false,
        crtFilterEnabled: false
    )

    init(
        startFullscreen: Bool,
        windowScale: Int,
        muteAudio: Bool,
        speedPercent: Int,
        upscaleMultiplier: Int,
        integerScaling: Bool,
        crtFilterEnabled: Bool
    ) {
        self.startFullscreen = startFullscreen
        self.windowScale = Self.clamp(windowScale, min: 1, max: 4)
        self.muteAudio = muteAudio
        self.speedPercent = Self.clamp(speedPercent, min: 25, max: 300)
        self.upscaleMultiplier = Self.clamp(upscaleMultiplier, min: 1, max: 8)
        self.integerScaling = integerScaling
        self.crtFilterEnabled = crtFilterEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startFullscreen: try container.decodeIfPresent(Bool.self, forKey: .startFullscreen) ?? false,
            windowScale: try container.decodeIfPresent(Int.self, forKey: .windowScale) ?? 1,
            muteAudio: try container.decodeIfPresent(Bool.self, forKey: .muteAudio) ?? false,
            speedPercent: try container.decodeIfPresent(Int.self, forKey: .speedPercent) ?? 100,
            upscaleMultiplier: try container.decodeIfPresent(Int.self, forKey: .upscaleMultiplier) ?? 2,
            integerScaling: try container.decodeIfPresent(Bool.self, forKey: .integerScaling) ?? false,
            crtFilterEnabled: try container.decodeIfPresent(Bool.self, forKey: .crtFilterEnabled) ?? false
        )

        // Legacy Mupen renderer settings are intentionally ignored during migration.
        _ = try container.decodeIfPresent(LegacyRendererBackend.self, forKey: .rendererBackend)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startFullscreen, forKey: .startFullscreen)
        try container.encode(windowScale, forKey: .windowScale)
        try container.encode(muteAudio, forKey: .muteAudio)
        try container.encode(speedPercent, forKey: .speedPercent)
        try container.encode(upscaleMultiplier, forKey: .upscaleMultiplier)
        try container.encode(integerScaling, forKey: .integerScaling)
        try container.encode(crtFilterEnabled, forKey: .crtFilterEnabled)
    }

    private enum CodingKeys: String, CodingKey {
        case startFullscreen
        case windowScale
        case muteAudio
        case speedPercent
        case upscaleMultiplier
        case integerScaling
        case crtFilterEnabled
        case rendererBackend
    }

    private enum LegacyRendererBackend: String, Codable {
        case auto
        case opengl
        case moltenVK
    }

    private static func clamp(_ value: Int, min lowerBound: Int, max upperBound: Int) -> Int {
        Swift.max(lowerBound, Swift.min(upperBound, value))
    }
}

struct InputMappingProfile: Codable, Equatable, Sendable {
    var profileName: String
    var notes: String

    static let standard = InputMappingProfile(
        profileName: "Standard",
        notes: "Use the embedded gopher64 controller defaults."
    )
}

struct Gopher64RuntimePaths: Codable, Equatable, Sendable {
    let bridgeLibraryURL: URL
    let supportDirectoryURL: URL
    let moltenVKLibraryURL: URL?
}

struct AppRuntimeDirectories: Codable, Equatable, Sendable {
    let root: URL
    let configDirectory: URL
    let dataDirectory: URL
    let cacheDirectory: URL
    let logDirectory: URL
}

struct RenderSurfaceDescriptor: Equatable, Sendable {
    let surfaceID: UInt64
    let generation: UInt64
    let windowHandle: UInt
    let viewHandle: UInt
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let backingScaleFactor: Double
    let revision: UInt64

    init(
        surfaceID: UInt64 = 1,
        generation: UInt64 = 1,
        windowHandle: UInt,
        viewHandle: UInt,
        logicalWidth: Int,
        logicalHeight: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        backingScaleFactor: Double,
        revision: UInt64
    ) {
        self.surfaceID = surfaceID
        self.generation = generation
        self.windowHandle = windowHandle
        self.viewHandle = viewHandle
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.backingScaleFactor = backingScaleFactor
        self.revision = revision
    }

    init(
        windowHandle: UInt,
        viewHandle: UInt,
        width: Int,
        height: Int,
        backingScaleFactor: Double
    ) {
        let pixelWidth = Int((Double(width) * backingScaleFactor).rounded())
        let pixelHeight = Int((Double(height) * backingScaleFactor).rounded())
        self.init(
            surfaceID: 1,
            generation: 1,
            windowHandle: windowHandle,
            viewHandle: viewHandle,
            logicalWidth: width,
            logicalHeight: height,
            pixelWidth: max(pixelWidth, 1),
            pixelHeight: max(pixelHeight, 1),
            backingScaleFactor: backingScaleFactor,
            revision: 1
        )
    }

    var width: Int { logicalWidth }
    var height: Int { logicalHeight }

    var isValid: Bool {
        surfaceID != 0 &&
            generation != 0 &&
            windowHandle != 0 &&
            viewHandle != 0 &&
            logicalWidth > 0 &&
            logicalHeight > 0 &&
            pixelWidth > 0 &&
            pixelHeight > 0 &&
            backingScaleFactor > 0 &&
            revision > 0
    }

    func matchesSurfaceIdentity(of other: RenderSurfaceDescriptor) -> Bool {
        surfaceID == other.surfaceID && generation == other.generation
    }

    func matchesCommittedGeometry(of other: RenderSurfaceDescriptor) -> Bool {
        matchesSurfaceIdentity(of: other) &&
            windowHandle == other.windowHandle &&
            viewHandle == other.viewHandle &&
            logicalWidth == other.logicalWidth &&
            logicalHeight == other.logicalHeight &&
            pixelWidth == other.pixelWidth &&
            pixelHeight == other.pixelHeight &&
            backingScaleFactor == other.backingScaleFactor
    }

    func matchesHandles(of other: RenderSurfaceDescriptor) -> Bool {
        windowHandle == other.windowHandle && viewHandle == other.viewHandle
    }
}

struct CoreRuntimeMetrics: Equatable, Sendable {
    let pumpTickCount: UInt64
    let viCount: UInt64
    let renderFrameCount: UInt64
    let presentCount: UInt64
    let frameRateHz: Double
    let pendingCommandCount: UInt64
    let runtimeState: Int32

    static let zero = CoreRuntimeMetrics(
        pumpTickCount: 0,
        viCount: 0,
        renderFrameCount: 0,
        presentCount: 0,
        frameRateHz: 0,
        pendingCommandCount: 0,
        runtimeState: 0
    )
}

struct CoreHostConfiguration: Equatable, Sendable {
    let romIdentity: ROMIdentity
    let runtimePaths: Gopher64RuntimePaths?
    let directories: AppRuntimeDirectories
    let renderSurface: RenderSurfaceDescriptor?
    let settings: CoreUserSettings
    let inputMapping: InputMappingProfile
}

enum CoreRuntimeEvent: Equatable, Sendable {
    case runtimeTerminated(String)
    case frameRateUpdated(Double)
}

@MainActor
protocol CoreHosting: AnyObject {
    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot
    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws
    func pumpEvents() async -> CoreRuntimeEvent?
    func pause() async throws
    func resume() async throws -> SessionSnapshot
    func reset() async throws
    func saveState(slot: Int) async throws
    func saveProtectedCloseState(slot: Int) async throws
    func loadState(slot: Int) async throws
    func loadProtectedCloseState(slot: Int) async throws
    func updateSettings(_ settings: CoreUserSettings) async throws
    func updateInputMapping(_ mapping: InputMappingProfile) async throws
    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws
    func releaseKeyboardInput() async throws
    func stop() async throws
    func dispose() async throws
}
