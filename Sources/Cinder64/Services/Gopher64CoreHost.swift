import Foundation
import OSLog

@MainActor
final class Gopher64CoreHost: CoreHosting {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.patricedery.Cinder64",
        category: "Runtime"
    )

    private let logStore: LogStore
    private let metricsArtifactStore: RuntimeMetricsArtifactStore
    private let executor: Gopher64CoreExecutor
    private var currentSnapshot = SessionSnapshot.idle
    private var lastLoggedFrameCount: UInt64 = 0
    private var lastFrameLogAt: Date?
    private var heldKeyboardScancodes: Set<Int32> = []

    init(
        logStore: LogStore,
        runtimeLocator: BundledGopher64RuntimeLocator = BundledGopher64RuntimeLocator()
    ) {
        self.logStore = logStore
        self.metricsArtifactStore = RuntimeMetricsArtifactStore(logStore: logStore)
        self.executor = Gopher64CoreExecutor(logStore: logStore, runtimeLocator: runtimeLocator)
    }

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> SessionSnapshot {
        let interval = Self.signposter.beginInterval("Open ROM")
        recordStartupPhase("open-requested")
        guard let renderSurface = configuration.renderSurface, renderSurface.isValid else {
            Self.signposter.endInterval("Open ROM", interval)
            throw Gopher64CoreHostError.renderSurfaceUnavailable
        }

        do {
            let runtime = try await executor.openROM(at: url, configuration: configuration)
            recordStartupPhase("surface-attached")
            recordStartupPhase("rom-opened")
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
            recordMetricsIfAvailable()
            Self.signposter.endInterval("Open ROM", interval)
            return currentSnapshot
        } catch {
            recordMetricsError(error.localizedDescription)
            Self.signposter.endInterval("Open ROM", interval)
            throw error
        }
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor) async throws {
        let interval = Self.signposter.beginInterval("Update Surface")
        do {
            try executor.updateRenderSurface(descriptor)
            recordMetricsIfAvailable()
            Self.signposter.endInterval("Update Surface", interval)
        } catch {
            recordMetricsError(error.localizedDescription)
            Self.signposter.endInterval("Update Surface", interval)
            throw error
        }
    }

    func pumpEvents() async -> CoreRuntimeEvent? {
        let interval = Self.signposter.beginInterval("Pump Drain")
        defer { Self.signposter.endInterval("Pump Drain", interval) }
        let event = executor.pumpEvents()
        recordFrameCountIfNeeded()
        recordMetricsIfAvailable()
        if let frameRate = executor.frameRate(), abs(frameRate - currentSnapshot.fps) >= 0.1 {
            currentSnapshot.fps = frameRate
            return event ?? .frameRateUpdated(frameRate)
        }
        return event
    }

    private func recordFrameCountIfNeeded() {
        guard let metrics = executor.metrics() else {
            return
        }
        let count = metrics.renderFrameCount
        let now = Date.now
        let elapsed = lastFrameLogAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard elapsed >= 1.0 else {
            return
        }
        guard count != lastLoggedFrameCount else {
            return
        }
        logStore.record(
            "info",
            "frame_count=\(count) pump_tick_count=\(metrics.pumpTickCount) vi_count=\(metrics.viCount) present_count=\(metrics.presentCount)"
        )
        lastLoggedFrameCount = count
        lastFrameLogAt = now
    }

    func pause() async throws {
        let interval = Self.signposter.beginInterval("Pause")
        try executor.pause()
        currentSnapshot.emulationState = .paused
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Pause", interval)
    }

    func resume() async throws -> SessionSnapshot {
        let interval = Self.signposter.beginInterval("Resume")
        do {
            try executor.resume()
            currentSnapshot.emulationState = .running
            recordStartupPhase("resumed")
            recordMetricsIfAvailable()
            Self.signposter.endInterval("Resume", interval)
            return currentSnapshot
        } catch {
            recordMetricsError(error.localizedDescription)
            Self.signposter.endInterval("Resume", interval)
            throw error
        }
    }

    func reset() async throws {
        let interval = Self.signposter.beginInterval("Reset")
        try executor.reset()
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Reset", interval)
    }

    func saveState(slot: Int) async throws {
        let interval = Self.signposter.beginInterval("Save State")
        try executor.saveState(slot: slot)
        currentSnapshot.activeSaveSlot = slot
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Save State", interval)
    }

    func saveProtectedCloseState(slot: Int) async throws {
        let interval = Self.signposter.beginInterval("Save Protected Close State")
        try executor.saveState(slot: slot)
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Save Protected Close State", interval)
    }

    func loadState(slot: Int) async throws {
        let interval = Self.signposter.beginInterval("Load State")
        try executor.loadState(slot: slot)
        currentSnapshot.activeSaveSlot = slot
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Load State", interval)
    }

    func loadProtectedCloseState(slot: Int) async throws {
        let interval = Self.signposter.beginInterval("Load Protected Close State")
        try executor.loadState(slot: slot)
        recordMetricsIfAvailable()
        Self.signposter.endInterval("Load Protected Close State", interval)
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

    func enqueueKeyboardInput(_ event: EmbeddedKeyboardEvent) async throws {
        try executor.setKeyboardKey(scancode: event.scancode, pressed: event.isPressed)
        if event.isPressed {
            heldKeyboardScancodes.insert(event.scancode)
        } else {
            heldKeyboardScancodes.remove(event.scancode)
        }
    }

    func releaseKeyboardInput() async throws {
        guard heldKeyboardScancodes.isEmpty == false else { return }

        // Release every held key so the embedded runtime doesn't see them as
        // still-pressed after focus leaves the surface. Continue on individual
        // failures so one stuck key can't block the rest.
        var firstError: Error?
        for scancode in heldKeyboardScancodes {
            do {
                try executor.setKeyboardKey(scancode: scancode, pressed: false)
            } catch {
                firstError = firstError ?? error
                logStore.record(
                    "warning",
                    "releaseKeyboardInput failed for scancode=\(scancode): \(error.localizedDescription)"
                )
            }
        }
        heldKeyboardScancodes.removeAll()

        if let firstError {
            throw firstError
        }
    }

    func stop() async throws {
        let interval = Self.signposter.beginInterval("Stop")
        recordShutdownPhase("stop-requested")
        do {
            try await executor.stop()
            recordShutdownPhase("stopped")
            currentSnapshot = .idle
            heldKeyboardScancodes.removeAll()
            recordMetricsIfAvailable()
            Self.signposter.endInterval("Stop", interval)
        } catch {
            recordMetricsError(error.localizedDescription)
            Self.signposter.endInterval("Stop", interval)
            throw error
        }
    }

    func dispose() async throws {
        let interval = Self.signposter.beginInterval("Dispose")
        recordShutdownPhase("dispose-requested")
        do {
            try await executor.dispose()
            recordShutdownPhase("disposed")
            currentSnapshot = .idle
            heldKeyboardScancodes.removeAll()
            recordMetricsIfAvailable()
            Self.signposter.endInterval("Dispose", interval)
        } catch {
            recordMetricsError(error.localizedDescription)
            Self.signposter.endInterval("Dispose", interval)
            throw error
        }
    }

    private func recordStartupPhase(_ phase: String) {
        metricsArtifactStore.update { artifact in
            if artifact.startupPhases.contains(phase) == false {
                artifact.startupPhases.append(phase)
            }
        }
    }

    private func recordShutdownPhase(_ phase: String) {
        metricsArtifactStore.update { artifact in
            artifact.shutdownPhases.append(phase)
        }
    }

    private func recordMetricsIfAvailable() {
        guard let metrics = executor.metrics() else {
            return
        }

        metricsArtifactStore.update { artifact in
            artifact.pumpTickCount = metrics.pumpTickCount
            artifact.viCount = metrics.viCount
            artifact.renderFrameCount = metrics.renderFrameCount
            artifact.presentCount = metrics.presentCount
            artifact.currentFPS = metrics.frameRateHz
        }
    }

    private func recordMetricsError(_ message: String) {
        metricsArtifactStore.update { artifact in
            artifact.lastStructuredError = RuntimeMetricsArtifactError(message: message)
        }
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

    func openROM(at url: URL, configuration: CoreHostConfiguration) async throws -> (rendererName: String, frameRate: Double) {
        try await stopRuntimeIfNeeded()

        guard let renderSurface = configuration.renderSurface, renderSurface.isValid else {
            throw Gopher64CoreHostError.renderSurfaceUnavailable
        }

        let (bridge, session, createdNewSession) = try loadOrCreateBridgeSession(configuration: configuration)

        do {
            logSurfaceRequest("attach", descriptor: renderSurface)
            try bridge.attachSurface(renderSurface, session: session)
            logSurfaceEventIfAvailable(from: bridge, session: session)
            let runtime = try bridge.openROM(at: url, configuration: configuration, session: session)
            logSurfaceEventIfAvailable(from: bridge, session: session)
            return runtime
        } catch {
            if createdNewSession {
                bridge.destroy(session)
                self.bridge = nil
                self.session = nil
            } else {
                logStore.record(
                    "warning",
                    "Reusing the dormant gopher64 bridge session failed: \(error.localizedDescription). Recreating the bridge on the next launch."
                )
                try? await dispose()
            }
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
        do {
            try bridge.pumpEvents(session: session)
        } catch {
            let message = error.localizedDescription
            logStore.record("warning", "Embedded runtime pump failed: \(message)")
            return .runtimeTerminated(message)
        }
        guard bridge.runtimeState(session: session) == .inactive else {
            return nil
        }

        let message = bridge.lastError(session: session) ?? "The embedded gopher64 runtime exited unexpectedly."
        logStore.record("warning", "Embedded runtime became inactive: \(message)")
        do {
            try bridge.stop(session: session)
        } catch {
            logStore.record(
                "warning",
                "The gopher64 bridge reported an error while finalizing an inactive runtime: \(error.localizedDescription)"
            )
        }
        return .runtimeTerminated(message)
    }

    func frameCount() -> UInt64? {
        guard let bridge, let session else { return nil }
        return bridge.frameCount(session: session)
    }

    func frameRate() -> Double? {
        guard let bridge, let session else { return nil }
        return bridge.frameRate(session: session)
    }

    func metrics() -> CoreRuntimeMetrics? {
        guard let bridge, let session else { return nil }
        let metrics = bridge.metrics(session: session)
        return CoreRuntimeMetrics(
            pumpTickCount: metrics.pumpTickCount,
            viCount: metrics.viCount,
            renderFrameCount: metrics.renderFrameCount,
            presentCount: metrics.presentCount,
            frameRateHz: metrics.frameRateHz,
            pendingCommandCount: metrics.pendingCommandCount,
            runtimeState: metrics.runtimeState.rawValue
        )
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

    func stop() async throws {
        try await stopRuntimeIfNeeded()
    }

    func dispose() async throws {
        guard let bridge, let session else { return }
        self.bridge = nil
        self.session = nil

        do {
            try await performBridgeStop(bridge: bridge, session: session)
        } catch Gopher64CoreHostError.shutdownTimeout {
            logStore.record(
                "warning",
                "gopher64 bridge dispose timed out; abandoning the session handle without calling destroy"
            )
            // Rust timed out first and leaked the emulation thread; do not touch
            // a session struct the stuck thread may still be using.
            return
        } catch {
            logStore.record(
                "warning",
                "The gopher64 bridge reported an error while stopping before disposal: \(error.localizedDescription)"
            )
            bridge.destroy(session)
            throw error
        }

        bridge.destroy(session)
    }

    private func loadOrCreateBridgeSession(
        configuration: CoreHostConfiguration
    ) throws -> (bridge: Gopher64Bridge, session: Gopher64Bridge.Session, createdNewSession: Bool) {
        if let bridge, let session {
            return (bridge, session, false)
        }

        let runtimePaths = if let runtimePaths = configuration.runtimePaths {
            runtimePaths
        } else {
            try runtimeLocator.locate()
        }
        let bridge = try Gopher64Bridge(runtimePaths: runtimePaths)
        let session = try bridge.createSession()
        self.bridge = bridge
        self.session = session
        return (bridge, session, true)
    }

    private func stopRuntimeIfNeeded() async throws {
        guard let bridge, let session else { return }
        do {
            try await performBridgeStop(bridge: bridge, session: session)
        } catch Gopher64CoreHostError.shutdownTimeout {
            // The Rust runtime thread refused to join within its own timeout; the
            // bridge handle can no longer be trusted. Drop our references and let
            // the next ROM launch rebuild the bridge from scratch. Do not call
            // bridge.destroy(session) — the abandoned emulation thread may still
            // touch that session struct.
            logStore.record(
                "warning",
                "gopher64 bridge stop timed out; dropping the bridge handle so the host can continue"
            )
            self.bridge = nil
            self.session = nil
        } catch let error as Gopher64BridgeError {
            switch error {
            case let .commandFailed(context, status, message)
                where context == "stopping emulation" &&
                (status == .timeout || status == .panic || status == .runtimeError):
                logStore.record(
                    "warning",
                    "gopher64 bridge stop failed with \(status.description); dropping poisoned session handle: \(message)"
                )
                self.bridge = nil
                self.session = nil
                throw error
            default:
                throw error
            }
        }
    }

    private static let bridgeStopTimeout: Duration = .seconds(4)

    private func performBridgeStop(
        bridge: Gopher64Bridge,
        session: Gopher64Bridge.Session
    ) async throws {
        let timeout = Self.bridgeStopTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try bridge.stop(session: session)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Gopher64CoreHostError.shutdownTimeout
            }

            defer { group.cancelAll() }
            // Wait for whichever task finishes first.
            _ = try await group.next()
        }
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
    case shutdownTimeout

    var errorDescription: String? {
        switch self {
        case .renderSurfaceUnavailable:
            "Cinder64 needs a live render surface before it can launch gopher64."
        case .shutdownTimeout:
            "The gopher64 runtime did not stop in time; its worker thread has been abandoned so the app can continue."
        }
    }
}
