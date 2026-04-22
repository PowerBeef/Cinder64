import Foundation

/// Back-pressure policy for the per-frame pump tick.
///
/// Responsible for deferring a tick while some other work (typically
/// live window-resize) is in flight, and coalescing any ticks that
/// arrive during that time into a single follow-up pump when the block
/// is released. The actual cadence — whether ticks originate from a
/// `CADisplayLink` (the production path via
/// `NSView.displayLink(target:selector:)`) or a test-injected Timer —
/// is the caller's responsibility.
@MainActor
final class RuntimePumpCoordinator {
    typealias PumpHandler = () -> Void

    private let fallbackInterval: TimeInterval
    private var pumpHandler: PumpHandler
    private var fallbackTimer: Timer?
    private var isStarted = false
    private var isBlocked = false
    private var hasDeferredTick = false

    init(
        fallbackInterval: TimeInterval = 1.0 / 60.0,
        onPumpRequested: @escaping PumpHandler = {}
    ) {
        self.fallbackInterval = fallbackInterval
        self.pumpHandler = onPumpRequested
    }

    /// Kept for source compatibility with earlier versions; no longer
    /// exposes a CVDisplayLink (which was deprecated in macOS 15). The
    /// coordinator is always in "timer/external tick" mode now.
    var isUsingDisplayLinkForTesting: Bool { false }

    func setOnPumpRequested(_ handler: @escaping PumpHandler) {
        pumpHandler = handler
    }

    func start() {
        guard isStarted == false else { return }
        isStarted = true
        configureFallbackTimerIfNeeded()
    }

    func stop() {
        isStarted = false
        hasDeferredTick = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    func setBlocked(_ blocked: Bool) {
        isBlocked = blocked
        guard blocked == false, hasDeferredTick else { return }
        hasDeferredTick = false
        firePumpIfNeeded()
    }

    func requestPumpTickForTesting() {
        handleTick()
    }

    private func handleTick() {
        guard isStarted else { return }
        guard isBlocked == false else {
            hasDeferredTick = true
            return
        }

        firePumpIfNeeded()
    }

    private func firePumpIfNeeded() {
        pumpHandler()
    }

    private func configureFallbackTimerIfNeeded() {
        guard fallbackTimer == nil else { return }

        let timer = Timer(
            timeInterval: fallbackInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }
}
