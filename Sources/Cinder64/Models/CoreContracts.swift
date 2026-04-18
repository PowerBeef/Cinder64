import Foundation

struct CoreUserSettings: Codable, Equatable, Sendable {
    var startFullscreen: Bool
    var muteAudio: Bool
    var speedPercent: Int
    var upscaleMultiplier: Int
    var integerScaling: Bool
    var crtFilterEnabled: Bool

    static let `default` = CoreUserSettings(
        startFullscreen: false,
        muteAudio: false,
        speedPercent: 100,
        upscaleMultiplier: 2,
        integerScaling: false,
        crtFilterEnabled: false
    )

    init(
        startFullscreen: Bool,
        muteAudio: Bool,
        speedPercent: Int,
        upscaleMultiplier: Int,
        integerScaling: Bool,
        crtFilterEnabled: Bool
    ) {
        self.startFullscreen = startFullscreen
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
        try container.encode(muteAudio, forKey: .muteAudio)
        try container.encode(speedPercent, forKey: .speedPercent)
        try container.encode(upscaleMultiplier, forKey: .upscaleMultiplier)
        try container.encode(integerScaling, forKey: .integerScaling)
        try container.encode(crtFilterEnabled, forKey: .crtFilterEnabled)
    }

    private enum CodingKeys: String, CodingKey {
        case startFullscreen
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
    let windowHandle: UInt
    let viewHandle: UInt
    let width: Int
    let height: Int
    let backingScaleFactor: Double

    var isValid: Bool {
        windowHandle != 0 && viewHandle != 0 && width > 0 && height > 0 && backingScaleFactor > 0
    }
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
}

@MainActor
protocol CoreHosting: AnyObject {
    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot
    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws
    func pumpEvents() -> CoreRuntimeEvent?
    func pause() async throws
    func resume() async throws -> SessionSnapshot
    func reset() async throws
    func saveState(slot: Int) async throws
    func loadState(slot: Int) async throws
    func updateSettings(_ settings: CoreUserSettings) async throws
    func updateInputMapping(_ mapping: InputMappingProfile) async throws
    func setKeyboardKey(scancode: Int32, pressed: Bool) async throws
    func stop() async throws
}
