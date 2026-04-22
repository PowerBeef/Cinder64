import AppKit
import OSLog
import QuartzCore
import SwiftUI

struct RenderSurfaceView: View {
    let snapshot: SessionSnapshot
    let capturesKeyboardInput: Bool
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let pumpRuntimeEvents: () -> Void

    var body: some View {
        ZStack {
            RenderSurfaceHost(
                surfaceChanged: surfaceChanged,
                keyboardInputChanged: keyboardInputChanged,
                capturesKeyboardInput: capturesKeyboardInput,
                pumpRuntimeEvents: pumpRuntimeEvents
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(ShellPalette.strongLine)
            }

            if let overlay = SurfaceOverlayPresentation.content(for: snapshot) {
                SurfaceOverlayCard(content: overlay)
                    .padding(18)
            }
        }
        .frame(minHeight: 320)
        .background(ShellPalette.offBlack, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: ShellPalette.stageShadow, radius: 18, y: 8)
    }
}

private struct SurfaceOverlayCard: View {
    let content: SurfaceOverlayContent

    var body: some View {
        VStack(spacing: 10) {
            if content.tone == .info {
                ProgressView()
                    .controlSize(.regular)
                    .tint(toneColor)
            } else {
                Image(systemName: content.symbolName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(toneColor)
            }

            Text(content.title)
                .font(.headline)

            Text(content.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 17)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10))
        }
        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 6)
    }

    private var toneColor: Color {
        switch content.tone {
        case .info:
            ShellPalette.accent.opacity(0.88)
        case .warning:
            .orange.opacity(0.82)
        case .critical:
            .red.opacity(0.82)
        }
    }
}

private struct RenderSurfaceHost: NSViewRepresentable {
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let capturesKeyboardInput: Bool
    let pumpRuntimeEvents: () -> Void

    func makeNSView(context: Context) -> RenderSurfaceHostingView {
        let view = RenderSurfaceHostingView()
        view.surfaceChanged = surfaceChanged
        view.keyboardInputChanged = keyboardInputChanged
        view.setKeyboardCaptureEnabled(capturesKeyboardInput)
        view.pumpRuntimeEvents = pumpRuntimeEvents
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceHostingView, context: Context) {
        nsView.surfaceChanged = surfaceChanged
        nsView.keyboardInputChanged = keyboardInputChanged
        nsView.setKeyboardCaptureEnabled(capturesKeyboardInput)
        nsView.pumpRuntimeEvents = pumpRuntimeEvents
        nsView.publishDescriptorIfPossible()
    }
}

private final class RenderSurfaceHostingView: NSView {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.patricedery.Cinder64",
        category: "RenderSurface"
    )
    private static var nextSurfaceID: UInt64 = 1

    var surfaceChanged: (RenderSurfaceDescriptor?) -> Void = { _ in }
    var keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void = { _ in }
    var capturesKeyboardInput = false
    var pumpRuntimeEvents: () -> Void = {}

    private var eventPumpTimer: Timer?
    private var localKeyboardEventMonitor: Any?
    private var lastCommittedDescriptor: RenderSurfaceDescriptor?
    private var lastDeferredRevision: UInt64?
    private var eventPumpDeferredForLiveResize = false
    private let surfaceID: UInt64
    private var surfaceGeneration: UInt64

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        let identifier = Self.nextSurfaceID
        Self.nextSurfaceID = Self.nextSurfaceID &+ 1
        self.surfaceID = identifier
        self.surfaceGeneration = 1
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEventPumpIfNeeded()
        configureKeyboardEventMonitorIfNeeded()
        publishDescriptorIfPossible()
        focusHostForKeyboardInput()
    }

    override func layout() {
        super.layout()
        publishDescriptorIfPossible()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        publishDescriptorIfPossible(forceCommit: true)
        if eventPumpDeferredForLiveResize {
            eventPumpDeferredForLiveResize = false
            pumpRuntimeEvents()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        publishDescriptorIfPossible()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            invalidateEventPump()
            removeKeyboardEventMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        focusHostForKeyboardInput()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let keyboardEvent = keyboardEvent(from: event) {
            keyboardInputChanged(keyboardEvent)
            return
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if let keyboardEvent = keyboardEvent(from: event) {
            keyboardInputChanged(keyboardEvent)
            return
        }

        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if let keyboardEvent = keyboardEvent(from: event) {
            keyboardInputChanged(keyboardEvent)
            return
        }

        super.flagsChanged(with: event)
    }

    func publishDescriptorIfPossible(forceCommit: Bool = false) {
        let size = bounds.integral.size
        guard size.width > 0, size.height > 0, let window else {
            if lastCommittedDescriptor != nil {
                Self.logger.info("render-surface invalidated")
                if let lastCommittedDescriptor {
                    surfaceGeneration = lastCommittedDescriptor.generation &+ 1
                }
                lastCommittedDescriptor = nil
                lastDeferredRevision = nil
            }
            surfaceChanged(nil)
            return
        }

        let logicalWidth = Int(size.width)
        let logicalHeight = Int(size.height)
        let pixelWidth = max(Int((size.width * window.backingScaleFactor).rounded()), 1)
        let pixelHeight = max(Int((size.height * window.backingScaleFactor).rounded()), 1)

        let currentWindowHandle = UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque())
        let currentViewHandle = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())

        let generation: UInt64
        if let lastCommittedDescriptor {
            if lastCommittedDescriptor.windowHandle == currentWindowHandle &&
                lastCommittedDescriptor.viewHandle == currentViewHandle {
                generation = lastCommittedDescriptor.generation
            } else {
                generation = max(surfaceGeneration, lastCommittedDescriptor.generation &+ 1)
            }
        } else {
            generation = max(surfaceGeneration, 1)
        }

        let nextRevision: UInt64
        if let lastCommittedDescriptor,
           lastCommittedDescriptor.generation == generation,
           lastCommittedDescriptor.windowHandle == currentWindowHandle,
           lastCommittedDescriptor.viewHandle == currentViewHandle,
           lastCommittedDescriptor.logicalWidth == logicalWidth,
           lastCommittedDescriptor.logicalHeight == logicalHeight,
           lastCommittedDescriptor.pixelWidth == pixelWidth,
           lastCommittedDescriptor.pixelHeight == pixelHeight,
           lastCommittedDescriptor.backingScaleFactor == window.backingScaleFactor {
            nextRevision = lastCommittedDescriptor.revision
        } else if let lastCommittedDescriptor, lastCommittedDescriptor.generation == generation {
            nextRevision = lastCommittedDescriptor.revision &+ 1
        } else {
            nextRevision = 1
        }

        let descriptor = RenderSurfaceDescriptor(
            surfaceID: surfaceID,
            generation: generation,
            windowHandle: currentWindowHandle,
            viewHandle: currentViewHandle,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            backingScaleFactor: Double(window.backingScaleFactor),
            revision: nextRevision
        )

        let decision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: lastCommittedDescriptor,
            proposed: descriptor,
            isLiveResize: inLiveResize && forceCommit == false
        )

        applySurfacePublicationDecision(decision, proposedDescriptor: descriptor)
    }

    private func applySurfacePublicationDecision(
        _ decision: RenderSurfacePublicationDecision,
        proposedDescriptor: RenderSurfaceDescriptor
    ) {
        switch decision {
        case .clear:
            lastCommittedDescriptor = nil
            lastDeferredRevision = nil
            surfaceChanged(nil)
        case .noChange:
            syncMetalLayer(
                using: lastCommittedDescriptor ?? proposedDescriptor,
                commitsDrawableSize: true
            )
        case let .defer(descriptor):
            syncMetalLayer(
                using: lastCommittedDescriptor ?? descriptor,
                commitsDrawableSize: false
            )
            guard lastDeferredRevision != descriptor.revision else {
                return
            }
            lastDeferredRevision = descriptor.revision
            Self.logger.info(
                "render-surface deferred revision=\(descriptor.revision) logical=\(descriptor.logicalWidth)x\(descriptor.logicalHeight) pixel=\(descriptor.pixelWidth)x\(descriptor.pixelHeight) liveResize=true"
            )
        case let .publish(descriptor, kind):
            syncMetalLayer(using: descriptor, commitsDrawableSize: true)
            lastCommittedDescriptor = descriptor
            surfaceGeneration = descriptor.generation
            lastDeferredRevision = nil
            Self.logger.info(
                "render-surface published kind=\(kind.logValue, privacy: .public) surfaceID=\(descriptor.surfaceID) generation=\(descriptor.generation) revision=\(descriptor.revision) logical=\(descriptor.logicalWidth)x\(descriptor.logicalHeight) pixel=\(descriptor.pixelWidth)x\(descriptor.pixelHeight) scale=\(descriptor.backingScaleFactor, format: .fixed(precision: 2))"
            )
            surfaceChanged(descriptor)
        }
    }

    private func syncMetalLayer(using descriptor: RenderSurfaceDescriptor, commitsDrawableSize: Bool) {
        guard let window, let metalLayer = layer as? CAMetalLayer else {
            return
        }

        metalLayer.frame = bounds
        metalLayer.contentsScale = window.backingScaleFactor

        let drawableDescriptor = if commitsDrawableSize {
            descriptor
        } else {
            lastCommittedDescriptor ?? descriptor
        }

        metalLayer.drawableSize = CGSize(
            width: drawableDescriptor.pixelWidth,
            height: drawableDescriptor.pixelHeight
        )
    }

    func setKeyboardCaptureEnabled(_ capturesKeyboardInput: Bool) {
        let shouldRefocus = RenderSurfaceKeyboardFocusPolicy.shouldRefocus(
            previousCapturesKeyboardInput: self.capturesKeyboardInput,
            currentCapturesKeyboardInput: capturesKeyboardInput
        )
        self.capturesKeyboardInput = capturesKeyboardInput

        if shouldRefocus {
            focusHostForKeyboardInput()
        }
    }

    private func configureEventPumpIfNeeded() {
        guard eventPumpTimer == nil else { return }

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(handleEventPumpTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        eventPumpTimer = timer
    }

    private func invalidateEventPump() {
        eventPumpTimer?.invalidate()
        eventPumpTimer = nil
    }

    private func configureKeyboardEventMonitorIfNeeded() {
        guard localKeyboardEventMonitor == nil else { return }

        localKeyboardEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            guard self.capturesKeyboardInput, let window = self.window, window.isKeyWindow else {
                return event
            }

            if let eventWindow = event.window, eventWindow != window {
                return event
            }

            if let keyboardEvent = self.keyboardEvent(from: event) {
                self.keyboardInputChanged(keyboardEvent)
                return nil
            }

            return event
        }
    }

    private func removeKeyboardEventMonitor() {
        guard let localKeyboardEventMonitor else { return }
        NSEvent.removeMonitor(localKeyboardEventMonitor)
        self.localKeyboardEventMonitor = nil
    }

    private func focusHostForKeyboardInput() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            _ = window.makeFirstResponder(self)
        }
    }

    private func keyboardEvent(from event: NSEvent) -> EmbeddedKeyboardEvent? {
        switch event.type {
        case .flagsChanged:
            guard let scancode = EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: event.keyCode) else {
                return nil
            }

            let isPressed = switch event.keyCode {
            case 56, 60:
                event.modifierFlags.contains(.shift)
            case 59, 62:
                event.modifierFlags.contains(.control)
            default:
                false
            }

            return EmbeddedKeyboardEvent(scancode: scancode, isPressed: isPressed)
        case .keyDown:
            guard event.isARepeat == false else {
                return nil
            }
            fallthrough
        case .keyUp:
            guard let scancode = EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: event.keyCode) else {
                return nil
            }

            return EmbeddedKeyboardEvent(scancode: scancode, isPressed: event.type == .keyDown)
        default:
            return nil
        }
    }

    @objc private func handleEventPumpTimer(_: Timer) {
        if inLiveResize {
            eventPumpDeferredForLiveResize = true
            return
        }

        pumpRuntimeEvents()
    }
}

private extension RenderSurfaceChangeKind {
    var logValue: String {
        switch self {
        case .attach:
            "attach"
        case .resize:
            "resize"
        case .reattach:
            "reattach"
        }
    }
}
