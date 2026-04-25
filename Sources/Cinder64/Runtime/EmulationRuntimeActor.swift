import Foundation

enum RuntimeCommand: Equatable, Sendable {
    case openROM(URL, CoreHostConfiguration)
    case updateRenderSurface(RenderSurfaceDescriptor)
    case pump
    case pause
    case resume
    case reset
    case saveState(slot: Int)
    case saveProtectedCloseState(slot: Int)
    case loadState(slot: Int)
    case loadProtectedCloseState(slot: Int)
    case updateSettings(CoreUserSettings)
    case updateInputMapping(InputMappingProfile)
    case keyboard(EmbeddedKeyboardEvent)
    case releaseKeyboardInput
    case stop
    case dispose
}

enum RuntimeCommandResult: Equatable, Sendable {
    case none
    case skipped
    case snapshot(SessionSnapshot)
    case event(CoreRuntimeEvent?)
}

enum RuntimeEvent: Equatable, Sendable {
    case lifecycleChanged(RuntimeLifecycleState)
    case snapshotUpdated(SessionSnapshot)
    case metricsUpdated(CoreRuntimeMetrics)
    case failed(String)
    case shutdownCompleted
}

protocol EmulationRuntimeControlling: Sendable {
    func send(_ command: RuntimeCommand) async throws -> RuntimeCommandResult
}

actor EmulationRuntimeActor: EmulationRuntimeControlling {
    typealias CommandExecutor = @Sendable (RuntimeCommand) async throws -> RuntimeCommandResult

    private let execute: CommandExecutor
    private var isPumpInFlight = false

    init(execute: @escaping CommandExecutor) {
        self.execute = execute
    }

    func send(_ command: RuntimeCommand) async throws -> RuntimeCommandResult {
        let isPumpCommand = command == .pump
        if isPumpCommand {
            guard isPumpInFlight == false else {
                return .skipped
            }
            isPumpInFlight = true
        }
        defer {
            if isPumpCommand {
                isPumpInFlight = false
            }
        }

        return try await execute(command)
    }
}

@MainActor
final class RuntimeActorCoreHost: CoreHosting {
    private let runtime: EmulationRuntimeControlling

    init(runtime: EmulationRuntimeControlling) {
        self.runtime = runtime
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        switch try await runtime.send(.openROM(url, configuration)) {
        case let .snapshot(snapshot):
            return snapshot
        default:
            return .idle
        }
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {
        _ = try await runtime.send(.updateRenderSurface(descriptor))
    }

    func pumpEvents() async -> CoreRuntimeEvent? {
        do {
            switch try await runtime.send(.pump) {
            case let .event(event):
                return event
            default:
                return nil
            }
        } catch {
            return .runtimeTerminated(error.localizedDescription)
        }
    }

    func pause() async throws {
        _ = try await runtime.send(.pause)
    }

    func resume() async throws -> SessionSnapshot {
        switch try await runtime.send(.resume) {
        case let .snapshot(snapshot):
            return snapshot
        default:
            return .idle
        }
    }

    func reset() async throws {
        _ = try await runtime.send(.reset)
    }

    func saveState(slot: Int) async throws {
        _ = try await runtime.send(.saveState(slot: slot))
    }

    func saveProtectedCloseState(slot: Int) async throws {
        _ = try await runtime.send(.saveProtectedCloseState(slot: slot))
    }

    func loadState(slot: Int) async throws {
        _ = try await runtime.send(.loadState(slot: slot))
    }

    func loadProtectedCloseState(slot: Int) async throws {
        _ = try await runtime.send(.loadProtectedCloseState(slot: slot))
    }

    func updateSettings(_ settings: CoreUserSettings) async throws {
        _ = try await runtime.send(.updateSettings(settings))
    }

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {
        _ = try await runtime.send(.updateInputMapping(mapping))
    }

    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws {
        _ = try await runtime.send(.keyboard(event))
    }

    func releaseKeyboardInput() async throws {
        _ = try await runtime.send(.releaseKeyboardInput)
    }

    func stop() async throws {
        _ = try await runtime.send(.stop)
    }

    func dispose() async throws {
        _ = try await runtime.send(.dispose)
    }
}

@MainActor
func makeCoreHostRuntimeActor(coreHost: CoreHosting) -> EmulationRuntimeActor {
    let executor = MainActorCoreHostRuntimeExecutor(coreHost: coreHost)
    return EmulationRuntimeActor { command in
        try await executor.execute(command)
    }
}

@MainActor
func makeLiveRuntimeCoreHost(logStore: LogStore) -> CoreHosting {
    let coreHost = Gopher64CoreHost(logStore: logStore)
    let runtimeActor = makeCoreHostRuntimeActor(coreHost: coreHost)
    return RuntimeActorCoreHost(runtime: runtimeActor)
}

@MainActor
private final class MainActorCoreHostRuntimeExecutor: @unchecked Sendable {
    private let coreHost: CoreHosting

    init(coreHost: CoreHosting) {
        self.coreHost = coreHost
    }

    func execute(_ command: RuntimeCommand) async throws -> RuntimeCommandResult {
        switch command {
        case let .openROM(url, configuration):
            return .snapshot(try await coreHost.openROM(at: url, configuration: configuration))
        case let .updateRenderSurface(descriptor):
            try await coreHost.updateRenderSurface(descriptor)
            return .none
        case .pump:
            return .event(await coreHost.pumpEvents())
        case .pause:
            try await coreHost.pause()
            return .none
        case .resume:
            return .snapshot(try await coreHost.resume())
        case .reset:
            try await coreHost.reset()
            return .none
        case let .saveState(slot):
            try await coreHost.saveState(slot: slot)
            return .none
        case let .saveProtectedCloseState(slot):
            try await coreHost.saveProtectedCloseState(slot: slot)
            return .none
        case let .loadState(slot):
            try await coreHost.loadState(slot: slot)
            return .none
        case let .loadProtectedCloseState(slot):
            try await coreHost.loadProtectedCloseState(slot: slot)
            return .none
        case let .updateSettings(settings):
            try await coreHost.updateSettings(settings)
            return .none
        case let .updateInputMapping(mapping):
            try await coreHost.updateInputMapping(mapping)
            return .none
        case let .keyboard(event):
            try await coreHost.enqueueKeyboardInput(event)
            return .none
        case .releaseKeyboardInput:
            try await coreHost.releaseKeyboardInput()
            return .none
        case .stop:
            try await coreHost.stop()
            return .none
        case .dispose:
            try await coreHost.dispose()
            return .none
        }
    }
}
