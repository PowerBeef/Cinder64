import Foundation
import Observation

@MainActor
@Observable
final class EmulationSession {
    private let coreHost: CoreHosting
    let persistenceStore: PersistenceStore

    private(set) var snapshot: SessionSnapshot
    private(set) var recentGames: [RecentGameRecord]
    private(set) var activeSettings: CoreUserSettings
    private(set) var inputMapping: InputMappingProfile
    private(set) var renderSurface: RenderSurfaceDescriptor?
    private var pendingSurfaceWaiters: [UUID: CheckedContinuation<RenderSurfaceDescriptor, Never>]

    init(
        coreHost: CoreHosting,
        persistenceStore: PersistenceStore,
        snapshot: SessionSnapshot = .idle
    ) {
        self.coreHost = coreHost
        self.persistenceStore = persistenceStore
        self.snapshot = snapshot
        self.recentGames = (try? persistenceStore.recentGamesStore.loadRecords()) ?? []
        self.activeSettings = .default
        self.inputMapping = .standard
        self.renderSurface = nil
        self.pendingSurfaceWaiters = [:]
    }

    func openROM(url: URL) async throws {
        let romIdentity = try ROMIdentity.make(for: url)
        let settings = try persistenceStore.settingsStore.loadSettings(for: romIdentity) ?? .default
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

        do {
            let renderSurface = await waitForValidRenderSurface()
            let configuration = CoreHostConfiguration(
                romIdentity: romIdentity,
                runtimePaths: nil,
                directories: persistenceStore.directories,
                renderSurface: renderSurface,
                settings: settings,
                inputMapping: inputMapping
            )

            _ = try await coreHost.openROM(at: url, configuration: configuration)
            snapshot = try await coreHost.resume()
            try persistenceStore.recentGamesStore.recordLaunch(romIdentity)
            recentGames = try persistenceStore.recentGamesStore.loadRecords()
            persistenceStore.logStore.record("info", "Opened \(romIdentity.displayName) using \(snapshot.rendererName)")
        } catch {
            snapshot = .idle
            throw error
        }
    }

    func pause() async throws {
        do {
            try await coreHost.pause()
            snapshot.emulationState = .paused
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
    }

    func resume() async throws {
        do {
            snapshot = try await coreHost.resume()
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

    func loadState(slot: Int) async throws {
        do {
            try await coreHost.loadState(slot: slot)
        } catch {
            markRuntimeFailure(message: error.localizedDescription)
            throw error
        }
        snapshot.activeSaveSlot = slot
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
            do {
                try await coreHost.setKeyboardKey(scancode: event.scancode, pressed: event.isPressed)
            } catch {
                persistenceStore.logStore.record(
                    "warning",
                    "setKeyboardKey failed scancode=\(event.scancode) pressed=\(event.isPressed): \(error.localizedDescription)"
                )
                markRuntimeFailure(message: error.localizedDescription)
            }
        }
    }

    func stop() async throws {
        try await coreHost.stop()
        snapshot = .idle
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
            snapshot.activeROM != nil,
            snapshot.emulationState != .booting
        else {
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

        if let event = coreHost.pumpEvents() {
            switch event {
            case let .runtimeTerminated(message):
                markRuntimeFailure(message: message)
            }
        }
    }

    func presentWarning(title: String, message: String) {
        snapshot.warningBanner = WarningBanner(title: title, message: message)
    }

    private func waitForValidRenderSurface() async -> RenderSurfaceDescriptor {
        if let renderSurface, renderSurface.isValid {
            return renderSurface
        }

        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            pendingSurfaceWaiters[waiterID] = continuation
        }
    }

    private func resumeSurfaceWaiters(with descriptor: RenderSurfaceDescriptor) {
        let waiters = pendingSurfaceWaiters.values
        pendingSurfaceWaiters.removeAll()

        for waiter in waiters {
            waiter.resume(returning: descriptor)
        }
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
    }
}
