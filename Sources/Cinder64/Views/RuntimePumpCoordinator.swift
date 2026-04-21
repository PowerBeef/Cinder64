import CoreVideo
import Foundation

@MainActor
final class RuntimePumpCoordinator {
    typealias PumpHandler = () -> Void

    private let useDisplayLink: Bool
    private let fallbackInterval: TimeInterval
    private var pumpHandler: PumpHandler
    private var displayLink: CVDisplayLink?
    private var fallbackTimer: Timer?
    private var isStarted = false
    private var isBlocked = false
    private var hasDeferredTick = false

    init(
        useDisplayLink: Bool = true,
        fallbackInterval: TimeInterval = 1.0 / 60.0,
        onPumpRequested: @escaping PumpHandler = {}
    ) {
        self.useDisplayLink = useDisplayLink
        self.fallbackInterval = fallbackInterval
        self.pumpHandler = onPumpRequested
    }

    deinit {
        CVDisplayLinkStop(displayLink ?? .init(bitPattern: 0)!)
        fallbackTimer?.invalidate()
    }

    var isUsingDisplayLinkForTesting: Bool {
        displayLink != nil
    }

    func setOnPumpRequested(_ handler: @escaping PumpHandler) {
        pumpHandler = handler
    }

    func start() {
        guard isStarted == false else { return }
        isStarted = true

        if configureDisplayLinkIfPossible() == false {
            configureFallbackTimerIfNeeded()
        }
    }

    func stop() {
        isStarted = false
        hasDeferredTick = false
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
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

    private func configureDisplayLinkIfPossible() -> Bool {
        guard useDisplayLink, displayLink == nil else {
            return displayLink != nil
        }

        var createdDisplayLink: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&createdDisplayLink) == kCVReturnSuccess,
              let createdDisplayLink else {
            return false
        }

        let handlerStatus = CVDisplayLinkSetOutputHandler(createdDisplayLink) { [weak self] _, _, _, _, _ in
            DispatchQueue.main.async {
                self?.handleTick()
            }
            return kCVReturnSuccess
        }

        guard handlerStatus == kCVReturnSuccess else {
            return false
        }

        guard CVDisplayLinkStart(createdDisplayLink) == kCVReturnSuccess else {
            return false
        }

        displayLink = createdDisplayLink
        return true
    }

    private func configureFallbackTimerIfNeeded() {
        guard fallbackTimer == nil else { return }

        let timer = Timer(
            timeInterval: fallbackInterval,
            repeats: true
        ) { [weak self] _ in
            self?.handleTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }
}
