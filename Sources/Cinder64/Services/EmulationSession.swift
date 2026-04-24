import Foundation
import Observation

enum EmulationSessionError: LocalizedError, Equatable {
    case renderSurfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .renderSurfaceUnavailable:
            "Cinder64 could not attach a valid render surface before the launch timed out."
        }
    }
}

@MainActor
@Observable
final class EmulationSession {
    private let coreHost: CoreHosting
    private let romIdentityResolver: ROMIdentityResolver
    private let renderSurfaceWaitTimeout: Duration
    let persistenceStore: PersistenceStore

    private(set) var snapshot: SessionSnapshot
    private(set) var recentGames: [RecentGameRecord]
    private(set) var activeSettings: CoreUserSettings
    private(set) var inputMapping: InputMappingProfile
    private(set) var renderSurface: RenderSurfaceDescriptor?
    private var deferredBootRenderSurface: RenderSurfaceDescriptor?
    private var pendingSurfaceWaiters: [UUID: CheckedContinuation<RenderSurfaceDescriptor, any Error>]
    private var pendingSurfaceTimeoutTasks: [UUID: Task<Void, Never>]
    private var isPumpInFlight = false
    private var lifecycle = RuntimeLifecycleStateMachine()

    /// Internal lifecycle phase tracked alongside `snapshot.emulationState`.
    /// Finer-grained than the five-case external state (includes
    /// `readyPaused`, `stopping`, `disposed`) so future UI surfaces or
    /// diagnostics can distinguish e.g. "waiting for Rust shutdown" from
    /// "just paused". Read-only to the outside world.
    var lifecycleState: RuntimeLifecycleState { lifecycle.state }

    init(
        coreHost: CoreHosting,
        persistenceStore: PersistenceStore,
        snapshot: SessionSnapshot = .idle,
        romIdentityResolver: ROMIdentityResolver = .live,
        renderSurfaceWaitTimeout: Duration = .seconds(5)
    ) {
        self.coreHost = coreHost
        self.romIdentityResolver = romIdentityResolver
        self.renderSurfaceWaitTimeout = renderSurfaceWaitTimeout
        self.persistenceStore = persistenceStore
        self.snapshot = snapshot
        self.recentGames = (try? persistenceStore.recentGamesStore.loadRecords()) ?? []
        self.activeSettings = .default
        self.inputMapping = .standard
        self.renderSurface = nil
        self.deferredBootRenderSurface = nil
        self.pendingSurfaceWaiters = [:]
        self.pendingSurfaceTimeoutTasks = [:]
    }

    /// Move the lifecycle machine forward. Invalid transitions are logged
    /// as warnings (helpful for catching programming bugs early) and the
    /// state is forced anyway, so the machine never gets wedged in a way
    /// that would break user-visible snapshot-driven behavior.
    private func advanceLifecycle(to next: RuntimeLifecycleState) {
        do {
            try lifecycle.transition(to: next)
        } catch {
            persistenceStore.logStore.record(
                "warning",
                "lifecycle transition rejected: \(error.localizedDescription)"
            )
            lifecycle.force(next)
        }
    }

    func resolveROMIdentity(for url: URL) async throws -> ROMIdentity {
        try await romIdentityResolver.identity(for: url)
    }

    func openROM(url: URL) async throws {
        let romIdentity = try await resolveROMIdentity(for: url)
        let settings = try persistenceStore.settingsStore.loadSettings(for: romIdentity) ?? .default
        deferredBootRenderSurface = nil
        activeSettings = settings
        snapshot = SessionSnapshot(
            emulationState: .booting,
            activeROM: romIdentity,
            rendererName: snapshot.rendererName,
            fps: 0,
            videoMode: .none,
            audioMuted: settings.muteAudio,
            activeSaveSlot: 0,
            warningBanner: nil
        )
        advanceLifecycle(to: .booting)

        do {
            let renderSurface = try await waitForValidRenderSurface()
            let configuration = CoreHostConfiguration(
                romIdentity: romIdentity,
                runtimePaths: nil,
                directories: persistenceStore.directories,
                renderSurface: renderSurface,
                settings: settings,
                inputMapping: inputMapping
            )

            _ = try await coreHost.openROM(at: url, configuration: configuration)
            advanceLifecycle(to: .readyPaused)
            snapshot = try await coreHost.resume()
            advanceLifecycle(to: .running)
            try await replayDeferredBootRenderSurfaceIfNeeded(initialDescriptor: renderSurface)
            try persistenceStore.recentGamesStore.recordLaunch(romIdentity)
            recentGames = try persistenceStore.recentGamesStore.loadRecords()
            persistenceStore.logStore.record("info", "Opened \(romIdentity.displayName) using \(snapshot.rendererName)")
        } catch {
            deferredBootRenderSurface = nil
            snapshot = .idle
            advanceLifecycle(to: .stopped)
            throw error
        }
    }

    func pause() async throws {
        do {
            try await coreHost.pause()
            snapshot.emulationState = .paused
            advanceLifecycle(to: .paused)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
    }

    func resume() async throws {
        do {
            snapshot = try await coreHost.resume()
            advanceLifecycle(to: .running)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
    }

    func reset() async throws {
        do {
            try await coreHost.reset()
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
    }

    func saveState(slot: Int) async throws {
        do {
            try await coreHost.saveState(slot: slot)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
        guard let identity = snapshot.activeROM else { return }
        try persistenceStore.saveStateStore.recordSaveState(
            for: identity,
            slot: slot,
            rendererName: snapshot.rendererName
        )
        snapshot.activeSaveSlot = slot
    }

    func saveProtectedCloseState() async throws {
        do {
            try await coreHost.saveProtectedCloseState(slot: SaveStateMetadataStore.protectedCloseSlot)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
        guard let identity = snapshot.activeROM else { return }
        try persistenceStore.saveStateStore.recordSaveState(
            for: identity,
            slot: SaveStateMetadataStore.protectedCloseSlot,
            rendererName: snapshot.rendererName,
            kind: .protectedClose
        )
    }

    func loadState(slot: Int) async throws {
        do {
            try await coreHost.loadState(slot: slot)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
        snapshot.activeSaveSlot = slot
    }

    func loadProtectedCloseState() async throws {
        do {
            try await coreHost.loadProtectedCloseState(slot: SaveStateMetadataStore.protectedCloseSlot)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
    }

    func updateSettings(_ settings: CoreUserSettings) async throws {
        activeSettings = settings
        if let identity = snapshot.activeROM {
            try persistenceStore.settingsStore.saveSettings(settings, for: identity)
        }
        do {
            try await coreHost.updateSettings(settings)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
        snapshot.audioMuted = settings.muteAudio
    }

    func updateInputMapping(_ mapping: InputMappingProfile) async throws {
        inputMapping = mapping
        try await coreHost.updateInputMapping(mapping)
    }

    func handleKeyboardInput(_ event: EmbeddedKeyboardEvent) {
        guard snapshot.activeROM != nil else {
            persistenceStore.logStore.record("info", "keyboard input ignored: no active ROM")
            return
        }

        guard snapshot.emulationState == .running || snapshot.emulationState == .paused else {
            persistenceStore.logStore.record(
                "info",
                "keyboard input ignored: emulationState=\(snapshot.emulationState.rawValue)"
            )
            return
        }

        Task {
            // Re-check once the task body actually runs — a pump task queued
            // ahead of us may have marked the runtime as failed in the
            // interim.
            guard snapshot.emulationState == .running || snapshot.emulationState == .paused else {
                persistenceStore.logStore.record(
                    "info",
                    "keyboard input ignored: emulationState=\(snapshot.emulationState.rawValue)"
                )
                return
            }
            do {
                try await coreHost.enqueueKeyboardInput(event)
            } catch {
                persistenceStore.logStore.record(
                    "warning",
                    "enqueueKeyboardInput failed scancode=\(event.scancode) pressed=\(event.isPressed): \(error.localizedDescription)"
                )
                markRuntimeFailure(message: error.localizedDescription)
            }
        }
    }

    func releaseKeyboardInput() {
        Task {
            do {
                try await coreHost.releaseKeyboardInput()
            } catch {
                persistenceStore.logStore.record(
                    "warning",
                    "releaseKeyboardInput failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func stop() async throws {
        advanceLifecycle(to: .stopping)
        failAllSurfaceWaiters(throwing: CancellationError())
        await releaseKeyboardInputBeforeRuntimeBoundary()
        do {
            try await coreHost.stop()
            deferredBootRenderSurface = nil
            snapshot = .idle
            advanceLifecycle(to: .stopped)
        } catch {
            // Shutdown errors — notably the Rust 3-second MoltenVK-wedge
            // timeout and the Swift 4-second task-group race that backs
            // it up — leave the emulation thread intentionally
            // abandoned but the Swift-side state fully recoverable. If
            // we rethrow here the close-game coordinator stalls with
            // the error pinned to the sheet and the user has no way to
            // recover except Force Quit. Force-reset instead, leave a
            // warning banner the home shell surfaces, and return
            // successfully — the user's close intent is honored.
            forceResetAfterShutdownFailure(error: error)
        }
    }

    func dispose() async throws {
        advanceLifecycle(to: .stopping)
        failAllSurfaceWaiters(throwing: CancellationError())
        await releaseKeyboardInputBeforeRuntimeBoundary()
        do {
            try await coreHost.dispose()
            deferredBootRenderSurface = nil
            snapshot = .idle
            advanceLifecycle(to: .disposed)
        } catch {
            // Same recovery policy as stop() — see the comment above.
            // For dispose the terminal state is .disposed (process
            // tear-down path) rather than .stopped, but the effect on
            // the Swift state is identical: clean slate, warning
            // surfaced, caller sees success.
            forceResetAfterShutdownFailure(error: error, terminal: .disposed)
        }
    }

    private func forceResetAfterShutdownFailure(
        error: Error,
        terminal: RuntimeLifecycleState = .stopped
    ) {
        persistenceStore.logStore.record(
            "warning",
            "session shutdown failed; forcing Swift-side cleanup: \(error.localizedDescription)"
        )
        deferredBootRenderSurface = nil
        snapshot = SessionSnapshot(
            emulationState: .stopped,
            activeROM: nil,
            rendererName: snapshot.rendererName,
            fps: 0,
            videoMode: .none,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: WarningBanner(
                title: "Emulator shutdown timed out",
                message: "The embedded runtime didn't stop cleanly. The session has been reset; you can open another ROM."
            )
        )
        advanceLifecycle(to: terminal)
    }

    func updateRenderSurface(_ descriptor: RenderSurfaceDescriptor?) {
        let previousDescriptor = renderSurface
        renderSurface = descriptor

        if let descriptor, descriptor.isValid {
            resumeSurfaceWaiters(with: descriptor)
        }

        guard
            let descriptor,
            descriptor.isValid,
            descriptor != previousDescriptor,
            snapshot.activeROM != nil
        else {
            return
        }

        if snapshot.emulationState == .booting {
            deferredBootRenderSurface = descriptor
            return
        }

        Task {
            do {
                try await coreHost.updateRenderSurface(descriptor)
            } catch {
                persistenceStore.logStore.record(
                    "warning",
                    "render-surface update failed revision=\(descriptor.revision): \(error.localizedDescription)"
                )
                markRuntimeFailure(message: error.localizedDescription)
            }
        }
    }

    func pumpRuntimeEvents() {
        guard snapshot.activeROM != nil else { return }
        // Drop overlapping pump ticks while an earlier pump is still awaiting
        // the core host. Keeps concurrent pumps off the Rust bridge and
        // matches the serialization contract the tests assert.
        guard isPumpInFlight == false else { return }
        isPumpInFlight = true

        Task {
            defer { isPumpInFlight = false }
            let event = await coreHost.pumpEvents()
            if let event {
                switch event {
                case let .frameRateUpdated(frameRate):
                    snapshot.fps = frameRate
                case let .runtimeTerminated(message):
                    markRuntimeFailure(message: message)
                }
            }
        }
    }

    func presentWarning(title: String, message: String) {
        snapshot.warningBanner = WarningBanner(title: title, message: message)
    }

    func dismissWarningBanner() {
        snapshot.warningBanner = nil
    }

    private func releaseKeyboardInputBeforeRuntimeBoundary() async {
        guard snapshot.activeROM != nil else {
            return
        }

        do {
            try await coreHost.releaseKeyboardInput()
        } catch {
            persistenceStore.logStore.record(
                "warning",
                "releaseKeyboardInput before runtime boundary failed: \(error.localizedDescription)"
            )
        }
    }

    private func waitForValidRenderSurface() async throws -> RenderSurfaceDescriptor {
        if let renderSurface, renderSurface.isValid {
            return renderSurface
        }

        let waiterID = UUID()
        defer {
            pendingSurfaceTimeoutTasks.removeValue(forKey: waiterID)?.cancel()
            pendingSurfaceWaiters.removeValue(forKey: waiterID)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingSurfaceWaiters[waiterID] = continuation
                pendingSurfaceTimeoutTasks[waiterID] = Task { [weak self, renderSurfaceWaitTimeout] in
                    do {
                        try await Task.sleep(for: renderSurfaceWaitTimeout)
                        await MainActor.run {
                            self?.failSurfaceWaiter(
                                id: waiterID,
                                throwing: EmulationSessionError.renderSurfaceUnavailable
                            )
                        }
                    } catch {
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failSurfaceWaiter(id: waiterID, throwing: CancellationError())
            }
        }
    }

    private func resumeSurfaceWaiters(with descriptor: RenderSurfaceDescriptor) {
        let waiters = pendingSurfaceWaiters.values
        let timeoutTasks = pendingSurfaceTimeoutTasks.values
        pendingSurfaceWaiters.removeAll()
        pendingSurfaceTimeoutTasks.removeAll()

        for task in timeoutTasks {
            task.cancel()
        }

        for waiter in waiters {
            waiter.resume(returning: descriptor)
        }
    }

    private func failSurfaceWaiter(id: UUID, throwing error: Error) {
        guard let waiter = pendingSurfaceWaiters.removeValue(forKey: id) else {
            return
        }

        pendingSurfaceTimeoutTasks.removeValue(forKey: id)?.cancel()
        waiter.resume(throwing: error)
    }

    private func failAllSurfaceWaiters(throwing error: Error) {
        let waiters = pendingSurfaceWaiters.values
        let timeoutTasks = pendingSurfaceTimeoutTasks.values
        pendingSurfaceWaiters.removeAll()
        pendingSurfaceTimeoutTasks.removeAll()

        for task in timeoutTasks {
            task.cancel()
        }

        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    private func replayDeferredBootRenderSurfaceIfNeeded(initialDescriptor: RenderSurfaceDescriptor) async throws {
        guard let deferredBootRenderSurface else {
            return
        }

        self.deferredBootRenderSurface = nil

        guard deferredBootRenderSurface != initialDescriptor else {
            return
        }

        try await coreHost.updateRenderSurface(deferredBootRenderSurface)
    }

    private func markRuntimeFailure(message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureMessage = trimmedMessage.isEmpty
            ? "The embedded gopher64 runtime exited unexpectedly."
            : trimmedMessage

        persistenceStore.logStore.record("warning", "Embedded runtime became inactive: \(failureMessage)")
        snapshot.emulationState = .failed
        snapshot.fps = 0
        snapshot.warningBanner = WarningBanner(
            title: "Emulation Stopped Unexpectedly",
            message: failureMessage
        )
        advanceLifecycle(to: .failed)
    }
}
