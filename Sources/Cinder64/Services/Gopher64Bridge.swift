import Cinder64BridgeABI
import Darwin
import Foundation

final class Gopher64Bridge: @unchecked Sendable {
    enum RuntimeState: Int32 {
        case inactive = 0
        case paused = 1
        case running = 2
    }

    struct Metrics: Equatable, Sendable {
        let pumpTickCount: UInt64
        let viCount: UInt64
        let renderFrameCount: UInt64
        let presentCount: UInt64
        let frameRateHz: Double
        let pendingCommandCount: UInt64
        let runtimeState: RuntimeState

        static let zero = Metrics(
            pumpTickCount: 0,
            viCount: 0,
            renderFrameCount: 0,
            presentCount: 0,
            frameRateHz: 0,
            pendingCommandCount: 0,
            runtimeState: .inactive
        )
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

        var surface = runtime.surfaceDescriptor(from: descriptor)
        try ensureSuccess(
            runtime.attachSurface(session.rawValue, &surface),
            session: session,
            context: "attaching the render surface"
        )
    }

    func updateSurface(_ descriptor: RenderSurfaceDescriptor, session: Session) throws {
        guard descriptor.isValid else {
            throw Gopher64BridgeError.invalidRenderSurface
        }

        var surface = runtime.surfaceDescriptor(from: descriptor)
        try ensureSuccess(
            runtime.updateSurface(session.rawValue, &surface),
            session: session,
            context: "updating the render surface"
        )
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration, session: Session) throws -> (rendererName: String, frameRate: Double) {
        let directories = configuration.directories
        try FileManager.default.createDirectory(at: directories.configDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directories.dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directories.cacheDirectory, withIntermediateDirectories: true)

        let settings = runtime.settings(from: configuration.settings)

        let result = url.path.withCString { romPath in
            directories.configDirectory.path.withCString { configPath in
                directories.dataDirectory.path.withCString { dataPath in
                    directories.cacheDirectory.path.withCString { cachePath in
                        if let moltenVKLibraryURL = runtimePaths.moltenVKLibraryURL {
                            return moltenVKLibraryURL.path.withCString { moltenVKPath in
                                var request = Cinder64OpenROMRequest(
                                    rom_path: romPath,
                                    config_dir: configPath,
                                    data_dir: dataPath,
                                    cache_dir: cachePath,
                                    molten_vk_library: moltenVKPath,
                                    settings: settings
                                )
                                return runtime.openROM(session.rawValue, &request)
                            }
                        }

                        var request = Cinder64OpenROMRequest(
                            rom_path: romPath,
                            config_dir: configPath,
                            data_dir: dataPath,
                            cache_dir: cachePath,
                            molten_vk_library: nil,
                            settings: settings
                        )
                        return runtime.openROM(session.rawValue, &request)
                    }
                }
            }
        }

        try ensureSuccess(result, session: session, context: "opening the ROM")
        let metrics = self.metrics(session: session)
        return (
            runtime.string(from: runtime.rendererName(session.rawValue)) ?? "gopher64",
            metrics.frameRateHz
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
        var runtimeSettings = runtime.settings(from: settings)
        try ensureSuccess(
            runtime.updateSettings(session.rawValue, &runtimeSettings),
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

    func pumpEvents(session: Session) throws {
        try ensureSuccess(runtime.pumpEvents(session.rawValue), session: session, context: "pumping runtime events")
    }

    func metrics(session: Session) -> Metrics {
        var raw = Cinder64Metrics(
            pump_tick_count: 0,
            vi_count: 0,
            render_frame_count: 0,
            present_count: 0,
            frame_rate_hz: 0,
            pending_command_count: 0,
            runtime_state: 0,
            reserved: 0
        )

        guard runtime.getMetrics(session.rawValue, &raw) == BridgeStatus.ok.rawValue else {
            return .zero
        }

        return Metrics(
            pumpTickCount: raw.pump_tick_count,
            viCount: raw.vi_count,
            renderFrameCount: raw.render_frame_count,
            presentCount: raw.present_count,
            frameRateHz: raw.frame_rate_hz,
            pendingCommandCount: raw.pending_command_count,
            runtimeState: RuntimeState(rawValue: raw.runtime_state) ?? .inactive
        )
    }

    func frameCount(session: Session) -> UInt64 {
        metrics(session: session).renderFrameCount
    }

    func runtimeState(session: Session) -> RuntimeState {
        metrics(session: session).runtimeState
    }

    func frameRate(session: Session) -> Double {
        metrics(session: session).frameRateHz
    }

    func lastError(session: Session) -> String? {
        lastErrorRecord(session: session).message
    }

    func surfaceEvent(session: Session) -> String? {
        runtime.string(from: runtime.surfaceEvent(session.rawValue))
    }

    private func lastErrorRecord(session: Session) -> BridgeFailureRecord {
        var error = Cinder64Error(code: 0, reserved: 0, message: nil)
        guard runtime.getLastError(session.rawValue, &error) == BridgeStatus.ok.rawValue else {
            return BridgeFailureRecord(status: .runtimeError, message: "Unknown gopher64 bridge error")
        }

        return BridgeFailureRecord(
            status: BridgeStatus(rawValue: Int32(error.code)) ?? .runtimeError,
            message: runtime.string(from: error.message)
        )
    }

    private func ensureSuccess(_ status: Int32, session: Session, context: String) throws {
        guard status == BridgeStatus.ok.rawValue else {
            let failure = lastErrorRecord(session: session)
            throw Gopher64BridgeError.commandFailed(
                context: context,
                status: failure.status,
                message: failure.message ?? "Unknown gopher64 bridge error"
            )
        }
    }
}

private struct BridgeFailureRecord {
    let status: BridgeStatus
    let message: String?
}

enum BridgeStatus: Int32, Sendable {
    case ok = 0
    case invalidArgument = 1
    case invalidState = 2
    case runtimeError = 3
    case notReady = 4
    case timeout = 5
    case panic = 6
    case abiMismatch = 7

    var description: String {
        switch self {
        case .ok:
            "ok"
        case .invalidArgument:
            "invalid_argument"
        case .invalidState:
            "invalid_state"
        case .runtimeError:
            "runtime_error"
        case .notReady:
            "not_ready"
        case .timeout:
            "timeout"
        case .panic:
            "panic"
        case .abiMismatch:
            "abi_mismatch"
        }
    }
}

private struct LoadedRuntime {
    typealias GetAPIFn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Cinder64BridgeAPI>?) -> Int32
    typealias CreateSessionFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias DestroySessionFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias AttachSurfaceFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64SurfaceDescriptor>?) -> Int32
    typealias UpdateSurfaceFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64SurfaceDescriptor>?) -> Int32
    typealias OpenROMFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64OpenROMRequest>?) -> Int32
    typealias PauseFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ResumeFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias ResetFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias SaveStateFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias LoadStateFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    typealias UpdateSettingsFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64Settings>?) -> Int32
    typealias SetKeyboardKeyFn = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32) -> Int32
    typealias StopFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias PumpEventsFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias GetLastErrorFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64Error>?) -> Int32
    typealias GetMetricsFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Cinder64Metrics>?) -> Int32
    typealias VersionFn = @convention(c) () -> UnsafePointer<CChar>?
    typealias RendererNameFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias SurfaceEventFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?

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
    let getLastError: GetLastErrorFn
    let getMetrics: GetMetricsFn
    let version: VersionFn
    let rendererName: RendererNameFn
    let surfaceEvent: SurfaceEventFn

    init(libraryURL: URL) throws {
        guard let handle = dlopen(libraryURL.path, RTLD_NOW) else {
            throw Gopher64BridgeError.dynamicLoadingFailed(
                path: libraryURL.path,
                message: dlerror().map { String(cString: $0) } ?? "Unknown dynamic loading error"
            )
        }

        let getAPI = try Self.loadSymbol(from: handle, named: "cinder64_bridge_get_api", as: GetAPIFn.self)
        var api = Cinder64BridgeAPI()
        let requestedVersion = UInt32(CINDER64_BRIDGE_ABI_VERSION)
        let status = withUnsafeMutablePointer(to: &api) {
            getAPI(requestedVersion, UInt32(MemoryLayout<Cinder64BridgeAPI>.size), $0)
        }

        guard status == BridgeStatus.ok.rawValue else {
            dlclose(handle)
            throw Gopher64BridgeError.abiPreflightFailed(
                "The bundled gopher64 bridge rejected ABI version \(requestedVersion) with status \(status)."
            )
        }

        guard api.abi_version == requestedVersion else {
            dlclose(handle)
            throw Gopher64BridgeError.abiPreflightFailed(
                "The bundled gopher64 bridge returned ABI version \(api.abi_version), expected \(requestedVersion)."
            )
        }

        guard api.struct_size == UInt32(MemoryLayout<Cinder64BridgeAPI>.size) else {
            dlclose(handle)
            throw Gopher64BridgeError.abiPreflightFailed("The bundled gopher64 bridge reported an unexpected API table size.")
        }

        guard api.surface_descriptor_size == UInt32(MemoryLayout<Cinder64SurfaceDescriptor>.size),
              api.settings_size == UInt32(MemoryLayout<Cinder64Settings>.size),
              api.open_rom_request_size == UInt32(MemoryLayout<Cinder64OpenROMRequest>.size),
              api.metrics_size == UInt32(MemoryLayout<Cinder64Metrics>.size),
              api.error_size == UInt32(MemoryLayout<Cinder64Error>.size) else {
            dlclose(handle)
            throw Gopher64BridgeError.abiPreflightFailed("The bundled gopher64 bridge reported incompatible struct sizes.")
        }

        self.handle = handle
        self.createSession = Self.castFunction(api.create_session, named: "create_session")
        self.destroySession = Self.castFunction(api.destroy_session, named: "destroy_session")
        self.attachSurface = Self.castFunction(api.attach_surface, named: "attach_surface")
        self.updateSurface = Self.castFunction(api.update_surface, named: "update_surface")
        self.openROM = Self.castFunction(api.open_rom, named: "open_rom")
        self.pause = Self.castFunction(api.pause, named: "pause")
        self.resume = Self.castFunction(api.resume, named: "resume")
        self.reset = Self.castFunction(api.reset, named: "reset")
        self.saveState = Self.castFunction(api.save_state, named: "save_state")
        self.loadState = Self.castFunction(api.load_state, named: "load_state")
        self.updateSettings = Self.castFunction(api.update_settings, named: "update_settings")
        self.setKeyboardKey = Self.castFunction(api.set_keyboard_key, named: "set_keyboard_key")
        self.stop = Self.castFunction(api.stop, named: "stop")
        self.pumpEvents = Self.castFunction(api.pump_events, named: "pump_events")
        self.getLastError = Self.castFunction(api.get_last_error, named: "get_last_error")
        self.getMetrics = Self.castFunction(api.get_metrics, named: "get_metrics")
        self.version = Self.castFunction(api.version, named: "version")
        self.rendererName = Self.castFunction(api.renderer_name, named: "renderer_name")
        self.surfaceEvent = Self.castFunction(api.surface_event, named: "surface_event")
    }

    func string(from value: UnsafePointer<CChar>?) -> String? {
        value.map { String(cString: $0) }
    }

    func surfaceDescriptor(from descriptor: RenderSurfaceDescriptor) -> Cinder64SurfaceDescriptor {
        Cinder64SurfaceDescriptor(
            surface_id: descriptor.surfaceID,
            generation: descriptor.generation,
            window_handle: descriptor.windowHandle,
            view_handle: descriptor.viewHandle,
            logical_width: Int32(descriptor.logicalWidth),
            logical_height: Int32(descriptor.logicalHeight),
            pixel_width: Int32(descriptor.pixelWidth),
            pixel_height: Int32(descriptor.pixelHeight),
            backing_scale_factor: descriptor.backingScaleFactor,
            revision: descriptor.revision
        )
    }

    func settings(from settings: CoreUserSettings) -> Cinder64Settings {
        Cinder64Settings(
            fullscreen: settings.startFullscreen ? 1 : 0,
            mute_audio: settings.muteAudio ? 1 : 0,
            speed_percent: Int32(settings.speedPercent),
            upscale_multiplier: Int32(settings.upscaleMultiplier),
            integer_scaling: settings.integerScaling ? 1 : 0,
            crt_filter: settings.crtFilterEnabled ? 1 : 0
        )
    }

    private static func loadSymbol<T>(from handle: UnsafeMutableRawPointer, named name: String, as _: T.Type) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown symbol error"
            throw Gopher64BridgeError.dynamicLoadingFailed(path: name, message: message)
        }

        return unsafeBitCast(symbol, to: T.self)
    }

    private static func castFunction<T>(_ address: UInt, named name: String) -> T {
        guard address != 0 else {
            fatalError("Missing bridge function pointer for \(name)")
        }
        return unsafeBitCast(address, to: T.self)
    }
}

enum Gopher64BridgeError: LocalizedError {
    case dynamicLoadingFailed(path: String, message: String)
    case abiPreflightFailed(String)
    case runtimeInitializationFailed(String)
    case invalidRenderSurface
    case commandFailed(context: String, status: BridgeStatus, message: String)

    var errorDescription: String? {
        switch self {
        case let .dynamicLoadingFailed(path, message):
            "Could not load the gopher64 bridge at \(path): \(message)"
        case let .abiPreflightFailed(message):
            message
        case let .runtimeInitializationFailed(message):
            message
        case .invalidRenderSurface:
            "Cinder64 does not have a valid render surface attached yet."
        case let .commandFailed(context, status, message):
            "The gopher64 bridge failed while \(context) [\(status.description)]: \(message)"
        }
    }
}
