import Darwin
import Foundation

final class Gopher64Bridge {
    enum RuntimeState: Int32 {
        case inactive = 0
        case paused = 1
        case running = 2
    }

    final class Session: @unchecked Sendable {
        fileprivate let rawValue: UnsafeMutableRawPointer

        fileprivate init(rawValue: UnsafeMutableRawPointer) {
            self.rawValue = rawValue
        }
    }

    private let runtime: LoadedRuntime
    let runtimePaths: Gopher64RuntimePaths

    init(runtimePaths: Gopher64RuntimePaths) throws {
        self.runtimePaths = runtimePaths
        self.runtime = try LoadedRuntime(libraryURL: runtimePaths.bridgeLibraryURL)
    }

    deinit {
        dlclose(runtime.handle)
    }

    var versionString: String {
        runtime.string(from: runtime.version()) ?? "gopher64"
    }

    func createSession() throws -> Session {
        guard let rawValue = runtime.createSession() else {
            throw Gopher64BridgeError.runtimeInitializationFailed("The bundled gopher64 bridge did not return a session handle.")
        }

        return Session(rawValue: rawValue)
    }

    func destroy(_ session: Session) {
        runtime.destroySession(session.rawValue)
    }

    func attachSurface(_ descriptor: RenderSurfaceDescriptor, session: Session) throws {
        guard descriptor.isValid else {
            throw Gopher64BridgeError.invalidRenderSurface
        }

        try ensureSuccess(
            runtime.attachSurface(
                session.rawValue,
                descriptor.windowHandle,
                descriptor.viewHandle,
                Int32(descriptor.logicalWidth),
                Int32(descriptor.logicalHeight),
                Int32(descriptor.pixelWidth),
                Int32(descriptor.pixelHeight),
                descriptor.backingScaleFactor,
                descriptor.revision
            ),
            session: session,
            context: "attaching the render surface"
        )
    }

    func updateSurface(_ descriptor: RenderSurfaceDescriptor, session: Session) throws {
        guard descriptor.isValid else {
            throw Gopher64BridgeError.invalidRenderSurface
        }

        try ensureSuccess(
            runtime.updateSurface(
                session.rawValue,
                descriptor.windowHandle,
                descriptor.viewHandle,
                Int32(descriptor.logicalWidth),
                Int32(descriptor.logicalHeight),
                Int32(descriptor.pixelWidth),
                Int32(descriptor.pixelHeight),
                descriptor.backingScaleFactor,
                descriptor.revision
            ),
            session: session,
            context: "updating the render surface"
        )
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration, session: Session) throws -> (rendererName: String, frameRate: Double) {
        let directories = configuration.directories
        try FileManager.default.createDirectory(at: directories.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directories.dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directories.cacheDirectory, withIntermediateDirectories: true)

        let result = url.path.withCString { romPath in
            directories.configDirectory.path.withCString { configPath in
                directories.dataDirectory.path.withCString { dataPath in
                    directories.cacheDirectory.path.withCString { cachePath in
                        if let moltenVKLibraryURL = runtimePaths.moltenVKLibraryURL {
                            return moltenVKLibraryURL.path.withCString { moltenVKPath in
                                runtime.openROM(
                                    session.rawValue,
                                    romPath,
                                    configPath,
                                    dataPath,
                                    cachePath,
                                    moltenVKPath,
                                    configuration.settings.startFullscreen ? 1 : 0,
                                    configuration.settings.muteAudio ? 1 : 0,
                                    Int32(configuration.settings.speedPercent),
                                    Int32(configuration.settings.upscaleMultiplier),
                                    configuration.settings.integerScaling ? 1 : 0,
                                    configuration.settings.crtFilterEnabled ? 1 : 0
                                )
                            }
                        }

                        return runtime.openROM(
                            session.rawValue,
                            romPath,
                            configPath,
                            dataPath,
                            cachePath,
                            nil,
                            configuration.settings.startFullscreen ? 1 : 0,
                            configuration.settings.muteAudio ? 1 : 0,
                            Int32(configuration.settings.speedPercent),
                            Int32(configuration.settings.upscaleMultiplier),
                            configuration.settings.integerScaling ? 1 : 0,
                            configuration.settings.crtFilterEnabled ? 1 : 0
                        )
                    }
                }
            }
        }

        try ensureSuccess(result, session: session, context: "opening the ROM")
        return (
            runtime.string(from: runtime.rendererName(session.rawValue)) ?? "gopher64",
            runtime.frameRate(session.rawValue)
        )
    }

    func pause(session: Session) throws {
        try ensureSuccess(runtime.pause(session.rawValue), session: session, context: "pausing emulation")
    }

    func resume(session: Session) throws {
        try ensureSuccess(runtime.resume(session.rawValue), session: session, context: "resuming emulation")
    }

    func reset(session: Session) throws {
        try ensureSuccess(runtime.reset(session.rawValue), session: session, context: "resetting emulation")
    }

    func saveState(slot: Int, session: Session) throws {
        try ensureSuccess(runtime.saveState(session.rawValue, Int32(slot)), session: session, context: "saving state")
    }

    func loadState(slot: Int, session: Session) throws {
        try ensureSuccess(runtime.loadState(session.rawValue, Int32(slot)), session: session, context: "loading state")
    }

    func updateSettings(_ settings: CoreUserSettings, session: Session) throws {
        try ensureSuccess(
            runtime.updateSettings(
                session.rawValue,
                settings.startFullscreen ? 1 : 0,
                settings.muteAudio ? 1 : 0,
                Int32(settings.speedPercent),
                Int32(settings.upscaleMultiplier),
                settings.integerScaling ? 1 : 0,
                settings.crtFilterEnabled ? 1 : 0
            ),
            session: session,
            context: "updating runtime settings"
        )
    }

    func setKeyboardKey(scancode: Int32, pressed: Bool, session: Session) throws {
        try ensureSuccess(
            runtime.setKeyboardKey(session.rawValue, scancode, pressed ? 1 : 0),
            session: session,
            context: "forwarding keyboard input"
        )
    }

    func stop(session: Session) throws {
        try ensureSuccess(runtime.stop(session.rawValue), session: session, context: "stopping emulation")
    }

    func pumpEvents(session: Session) {
        _ = runtime.pumpEvents(session.rawValue)
    }

    func frameCount(session: Session) -> UInt64 {
        runtime.frameCount(session.rawValue)
    }

    func runtimeState(session: Session) -> RuntimeState {
        RuntimeState(rawValue: runtime.runtimeState(session.rawValue)) ?? .inactive
    }

    func lastError(session: Session) -> String? {
        runtime.string(from: runtime.lastError(session.rawValue))
    }

    func surfaceEvent(session: Session) -> String? {
        runtime.string(from: runtime.surfaceEvent(session.rawValue))
    }

    private func ensureSuccess(_ result: Int32, session: Session, context: String) throws {
        guard result == 0 else {
            throw Gopher64BridgeError.commandFailed(
                context: context,
                message: runtime.string(from: runtime.lastError(session.rawValue)) ?? "Unknown gopher64 bridge error"
            )
        }
    }
}

private struct LoadedRuntime {
    typealias CreateSessionFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias DestroySessionFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias AttachSurfaceFn = @convention(c) (UnsafeMutableRawPointer?, UInt, UInt, Int32, Int32, Int32, Int32, Double, UInt64) -> Int32
    typealias UpdateSurfaceFn = @convention(c) (UnsafeMutableRawPointer?, UInt, UInt, Int32, Int32, Int32, Int32, Double, UInt64) -> Int32
    typealias OpenROMFn = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        Int32,
        Int32,
        Int32,
        Int32,
        Int32,
        Int32
    ) -> Int32
    typealias PauseFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ResumeFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ResetFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias SaveStateFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias LoadStateFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias UpdateSettingsFn = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32
    typealias SetKeyboardKeyFn = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Int32
    typealias StopFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias PumpEventsFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias LastErrorFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias SurfaceEventFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias VersionFn = @convention(c) () -> UnsafePointer<CChar>?
    typealias RendererNameFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias FrameRateFn = @convention(c) (UnsafeMutableRawPointer?) -> Double
    typealias FrameCountFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt64
    typealias RuntimeStateFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32

    let handle: UnsafeMutableRawPointer
    let createSession: CreateSessionFn
    let destroySession: DestroySessionFn
    let attachSurface: AttachSurfaceFn
    let updateSurface: UpdateSurfaceFn
    let openROM: OpenROMFn
    let pause: PauseFn
    let resume: ResumeFn
    let reset: ResetFn
    let saveState: SaveStateFn
    let loadState: LoadStateFn
    let updateSettings: UpdateSettingsFn
    let setKeyboardKey: SetKeyboardKeyFn
    let stop: StopFn
    let pumpEvents: PumpEventsFn
    let lastError: LastErrorFn
    let surfaceEvent: SurfaceEventFn
    let version: VersionFn
    let rendererName: RendererNameFn
    let frameRate: FrameRateFn
    let frameCount: FrameCountFn
    let runtimeState: RuntimeStateFn

    init(libraryURL: URL) throws {
        guard let handle = dlopen(libraryURL.path, RTLD_NOW) else {
            throw Gopher64BridgeError.dynamicLoadingFailed(
                path: libraryURL.path,
                message: dlerror().map { String(cString: $0) } ?? "Unknown dynamic loading error"
            )
        }

        self.handle = handle
        self.createSession = try Self.loadSymbol(from: handle, named: "cinder64_bridge_create_session", as: CreateSessionFn.self)
        self.destroySession = try Self.loadSymbol(from: handle, named: "cinder64_bridge_destroy_session", as: DestroySessionFn.self)
        self.attachSurface = try Self.loadSymbol(from: handle, named: "cinder64_bridge_attach_surface", as: AttachSurfaceFn.self)
        self.updateSurface = try Self.loadSymbol(from: handle, named: "cinder64_bridge_update_surface", as: UpdateSurfaceFn.self)
        self.openROM = try Self.loadSymbol(from: handle, named: "cinder64_bridge_open_rom", as: OpenROMFn.self)
        self.pause = try Self.loadSymbol(from: handle, named: "cinder64_bridge_pause", as: PauseFn.self)
        self.resume = try Self.loadSymbol(from: handle, named: "cinder64_bridge_resume", as: ResumeFn.self)
        self.reset = try Self.loadSymbol(from: handle, named: "cinder64_bridge_reset", as: ResetFn.self)
        self.saveState = try Self.loadSymbol(from: handle, named: "cinder64_bridge_save_state", as: SaveStateFn.self)
        self.loadState = try Self.loadSymbol(from: handle, named: "cinder64_bridge_load_state", as: LoadStateFn.self)
        self.updateSettings = try Self.loadSymbol(from: handle, named: "cinder64_bridge_update_settings", as: UpdateSettingsFn.self)
        self.setKeyboardKey = try Self.loadSymbol(from: handle, named: "cinder64_bridge_set_keyboard_key", as: SetKeyboardKeyFn.self)
        self.stop = try Self.loadSymbol(from: handle, named: "cinder64_bridge_stop", as: StopFn.self)
        self.pumpEvents = try Self.loadSymbol(from: handle, named: "cinder64_bridge_pump_events", as: PumpEventsFn.self)
        self.lastError = try Self.loadSymbol(from: handle, named: "cinder64_bridge_last_error", as: LastErrorFn.self)
        self.surfaceEvent = try Self.loadSymbol(from: handle, named: "cinder64_bridge_surface_event", as: SurfaceEventFn.self)
        self.version = try Self.loadSymbol(from: handle, named: "cinder64_bridge_version", as: VersionFn.self)
        self.rendererName = try Self.loadSymbol(from: handle, named: "cinder64_bridge_renderer_name", as: RendererNameFn.self)
        self.frameRate = try Self.loadSymbol(from: handle, named: "cinder64_bridge_frame_rate", as: FrameRateFn.self)
        self.frameCount = try Self.loadSymbol(from: handle, named: "cinder64_bridge_frame_count", as: FrameCountFn.self)
        self.runtimeState = try Self.loadSymbol(from: handle, named: "cinder64_bridge_runtime_state", as: RuntimeStateFn.self)
    }

    func string(from value: UnsafePointer<CChar>?) -> String? {
        value.map { String(cString: $0) }
    }

    private static func loadSymbol<T>(from handle: UnsafeMutableRawPointer, named name: String, as _: T.Type) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown symbol error"
            throw Gopher64BridgeError.dynamicLoadingFailed(path: name, message: message)
        }

        return unsafeBitCast(symbol, to: T.self)
    }
}

enum Gopher64BridgeError: LocalizedError {
    case dynamicLoadingFailed(path: String, message: String)
    case runtimeInitializationFailed(String)
    case invalidRenderSurface
    case commandFailed(context: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .dynamicLoadingFailed(path, message):
            "Could not load the gopher64 bridge at \(path): \(message)"
        case let .runtimeInitializationFailed(message):
            message
        case .invalidRenderSurface:
            "Cinder64 does not have a valid render surface attached yet."
        case let .commandFailed(context, message):
            "The gopher64 bridge failed while \(context): \(message)"
        }
    }
}
