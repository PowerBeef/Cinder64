import Foundation

@MainActor
final class Gopher64CoreHost: CoreHosting {
    private let logStore: LogStore
    private let executor: Gopher64CoreExecutor
    private var currentSnapshot = SessionSnapshot.idle
    private var lastLoggedFrameCount: UInt64 = 0
    private var lastFrameLogAt: Date?

    init(
        logStore: LogStore,
        runtimeLocator: BundledGopher64RuntimeLocator = BundledGopher64RuntimeLocator()
    ) {
        self.logStore = logStore
        self.executor = Gopher64CoreExecutor(logStore: logStore, runtimeLocator: runtimeLocator)
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        guard let renderSurface = configuration.renderSurface, renderSurface.isValid else {
            throw Gopher64CoreHostError.renderSurfaceUnavailable
        }

        let runtime = try executor.openROM(at: url, configuration: configuration)
        currentSnapshot = SessionSnapshot(
            emulationState: .paused,
            activeROM: configuration.romIdentity,
            rendererName: runtime.rendererName,
            fps: runtime.frameRate,
            videoMode: configuration.settings.startFullscreen ? .fullscreen : .windowed,
            audioMuted: configuration.settings.muteAudio,
            activeSaveSlot: 0,
            warningBanner: nil
        )
        return currentSnapshot
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {
        try executor.updateRenderSurface(descriptor)
    }

    func pumpEvents() -> CoreRuntimeEvent? {
        let event = executor.pumpEvents()
        recordFrameCountIfNeeded()
        return event
    }

    private func recordFrameCountIfNeeded() {
        guard let count = executor.frameCount() else {
            return
        }
        let now = Date.now
        let elapsed = lastFrameLogAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard elapsed >= 1.0 else {
            return
        }
        guard count != lastLoggedFrameCount else {
            return
        }
        logStore.record("info", "frame_count=\(count)")
        lastLoggedFrameCount = count
        lastFrameLogAt = now
    }

    func pause() async throws {
        try executor.pause()
        currentSnapshot.emulationState = .paused
    }

    func resume() async throws -> SessionSnapshot {
        try executor.resume()
        currentSnapshot.emulationState = .running
        return currentSnapshot
    }

    func reset() async throws {
        try executor.reset()
    }

    func saveState(slot: Int) async throws {
        try executor.saveState(slot: slot)
        currentSnapshot.activeSaveSlot = slot
    }

    func loadState(slot: Int) async throws {
        try executor.loadState(slot: slot)
        currentSnapshot.activeSaveSlot = slot
    }

    func updateSettings(_ settings: CoreUserSettings) async throws {
        let requestedVideoMode: VideoMode = settings.startFullscreen ? .fullscreen : .windowed
        let hasActiveRuntime = currentSnapshot.activeROM != nil &&
            currentSnapshot.emulationState != .stopped &&
            currentSnapshot.emulationState != .failed

        try executor.updateSettings(settings)
        currentSnapshot.audioMuted = settings.muteAudio
        if hasActiveRuntime, currentSnapshot.videoMode != requestedVideoMode {
            logStore.record(
                "info",
                "embedded fullscreen flag deferred until the next ROM launch while the host window mode changes immediately"
            )
            currentSnapshot.videoMode = requestedVideoMode
            return
        }

        currentSnapshot.videoMode = requestedVideoMode
    }

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {
        logStore.record("info", "Using input mapping profile: \(mapping.profileName)")
    }

    func setKeyboardKey(scancode: Int32, pressed: Bool) async throws {
        try executor.setKeyboardKey(scancode: scancode, pressed: pressed)
    }

    func stop() async throws {
        try executor.stop()
        currentSnapshot = .idle
    }
}

@MainActor
private final class Gopher64CoreExecutor {
    private let logStore: LogStore
    private let runtimeLocator: BundledGopher64RuntimeLocator

    private var bridge: Gopher64Bridge?
    private var session: Gopher64Bridge.Session?

    init(logStore: LogStore, runtimeLocator: BundledGopher64RuntimeLocator) {
        self.logStore = logStore
        self.runtimeLocator = runtimeLocator
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration) throws -> (rendererName: String, frameRate: Double) {
        try stopIfNeeded()

        guard let renderSurface = configuration.renderSurface, renderSurface.isValid else {
            throw Gopher64CoreHostError.renderSurfaceUnavailable
        }

        let runtimePaths = if let runtimePaths = configuration.runtimePaths {
            runtimePaths
        } else {
            try runtimeLocator.locate()
        }
        let bridge = try Gopher64Bridge(runtimePaths: runtimePaths)
        let session = try bridge.createSession()

        do {
            logSurfaceRequest("attach", descriptor: renderSurface)
            try bridge.attachSurface(renderSurface, session: session)
            logSurfaceEventIfAvailable(from: bridge, session: session)
            let runtime = try bridge.openROM(at: url, configuration: configuration, session: session)
            logSurfaceEventIfAvailable(from: bridge, session: session)
            self.bridge = bridge
            self.session = session
            return runtime
        } catch {
            bridge.destroy(session)
            throw error
        }
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) throws {
        guard let bridge, let session, descriptor.isValid else { return }
        logSurfaceRequest("update", descriptor: descriptor)
        try bridge.updateSurface(descriptor, session: session)
        logSurfaceEventIfAvailable(from: bridge, session: session)
    }

    func pumpEvents() -> CoreRuntimeEvent? {
        guard let bridge, let session else { return nil }
        bridge.pumpEvents(session: session)
        guard bridge.runtimeState(session: session) == .inactive else {
            return nil
        }

        let message = bridge.lastError(session: session) ?? "The embedded gopher64 runtime exited unexpectedly."
        logStore.record("warning", "Embedded runtime became inactive: \(message)")
        bridge.destroy(session)
        self.bridge = nil
        self.session = nil
        return .runtimeTerminated(message)
    }

    func frameCount() -> UInt64? {
        guard let bridge, let session else { return nil }
        return bridge.frameCount(session: session)
    }

    func pause() throws {
        guard let bridge, let session else { return }
        try bridge.pause(session: session)
    }

    func resume() throws {
        guard let bridge, let session else { return }
        try bridge.resume(session: session)
    }

    func reset() throws {
        guard let bridge, let session else { return }
        try bridge.reset(session: session)
    }

    func saveState(slot: Int) throws {
        guard let bridge, let session else { return }
        try bridge.saveState(slot: slot, session: session)
    }

    func loadState(slot: Int) throws {
        guard let bridge, let session else { return }
        try bridge.loadState(slot: slot, session: session)
    }

    func updateSettings(_ settings: CoreUserSettings) throws {
        guard let bridge, let session else { return }
        try bridge.updateSettings(settings, session: session)
    }

    func setKeyboardKey(scancode: Int32, pressed: Bool) throws {
        guard let bridge, let session else { return }
        try bridge.setKeyboardKey(scancode: scancode, pressed: pressed, session: session)
    }

    func stop() throws {
        try stopIfNeeded()
    }

    private func stopIfNeeded() throws {
        guard let bridge, let session else { return }

        do {
            try bridge.stop(session: session)
        } catch {
            logStore.record("warning", "The gopher64 bridge reported an error while stopping: \(error.localizedDescription)")
        }

        bridge.destroy(session)
        self.bridge = nil
        self.session = nil
    }

    private func logSurfaceRequest(_ kind: String, descriptor: RenderSurfaceDescriptor) {
        logStore.record(
            "info",
            "render-surface request kind=\(kind) revision=\(descriptor.revision) logical=\(descriptor.logicalWidth)x\(descriptor.logicalHeight) pixel=\(descriptor.pixelWidth)x\(descriptor.pixelHeight) scale=\(String(format: "%.2f", descriptor.backingScaleFactor))"
        )
    }

    private func logSurfaceEventIfAvailable(from bridge: Gopher64Bridge, session: Gopher64Bridge.Session) {
        guard let message = bridge.surfaceEvent(session: session), message.isEmpty == false else {
            return
        }
        logStore.record("info", message)
    }
}

enum Gopher64CoreHostError: LocalizedError {
    case renderSurfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .renderSurfaceUnavailable:
            "Cinder64 needs a live render surface before it can launch gopher64."
        }
    }
}
