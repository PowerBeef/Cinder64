import Foundation

@MainActor
final class RenderSurfaceCoordinator {
    let displayController: EmulatorDisplayController?

    var onSurfaceChanged: (RenderSurfaceDescriptor?) -> Void
    var onPumpTick: () -> Void
    private let setDisplayContentVisible: (Bool) -> Void

    private var currentSurface: RenderSurfaceDescriptor?
    private var pendingSurfaceWaiters: [UUID: CheckedContinuation<RenderSurfaceDescriptor, any Error>] = [:]
    private var pendingSurfaceTimeoutTasks: [UUID: Task<Void, Never>] = [:]

    init(
        displayController: EmulatorDisplayController? = EmulatorDisplayController(),
        onSurfaceChanged: @escaping (RenderSurfaceDescriptor?) -> Void = { _ in },
        onPumpTick: @escaping () -> Void = {},
        setDisplayContentVisible: ((Bool) -> Void)? = nil
    ) {
        self.displayController = displayController
        self.onSurfaceChanged = onSurfaceChanged
        self.onPumpTick = onPumpTick
        self.setDisplayContentVisible = setDisplayContentVisible ?? { visible in
            displayController?.setContentVisible(visible)
        }
    }

    func wireSurfaceCallbacks() {
        guard let surfaceView = displayController?.surfaceView else {
            return
        }

        surfaceView.surfaceChanged = { [weak self] descriptor in
            self?.publishSurface(descriptor)
        }
        surfaceView.pumpRuntimeEvents = { [weak self] in
            self?.requestPumpTick()
        }
    }

    func publishSurface(_ descriptor: RenderSurfaceDescriptor?) {
        currentSurface = descriptor
        onSurfaceChanged(descriptor)

        guard let descriptor, descriptor.isValid else {
            return
        }

        resumeSurfaceWaiters(with: descriptor)
    }

    func requestPumpTick() {
        onPumpTick()
    }

    func setPromptVisible(_ visible: Bool) {
        setDisplayContentVisible(visible == false)
    }

    func updateOverlay(for snapshot: SessionSnapshot) {
        displayController?.updateOverlay(for: snapshot)
    }

    func waitForValidSurface(timeout: Duration) async throws -> RenderSurfaceDescriptor {
        if let currentSurface, currentSurface.isValid {
            return currentSurface
        }

        let waiterID = UUID()
        defer {
            pendingSurfaceTimeoutTasks.removeValue(forKey: waiterID)?.cancel()
            pendingSurfaceWaiters.removeValue(forKey: waiterID)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingSurfaceWaiters[waiterID] = continuation
                pendingSurfaceTimeoutTasks[waiterID] = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
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

    func invalidate() {
        currentSurface = nil
        onSurfaceChanged(nil)
        failAllSurfaceWaiters(throwing: CancellationError())
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
}
