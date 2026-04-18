import AppKit
import OSLog
import QuartzCore
import SwiftUI

struct RenderSurfaceView: View {
    let snapshot: SessionSnapshot
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void
    let pumpRuntimeEvents: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gameplay Surface")
                .font(.headline)

            ZStack {
                RenderSurfaceHost(
                    surfaceChanged: surfaceChanged,
                    keyboardInputChanged: keyboardInputChanged,
                    capturesKeyboardInput: snapshot.activeROM != nil,
                    pumpRuntimeEvents: pumpRuntimeEvents
                )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06))
                    }

                VStack(spacing: 10) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 42))
                    Text(snapshot.activeROM?.displayName ?? "Open a ROM to Begin")
                        .font(.title3.weight(.semibold))
                    Text(surfaceMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(24)
            }
            .frame(minHeight: 340)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var surfaceMessage: String {
        switch snapshot.emulationState {
        case .stopped:
            "The native render host is attached. Opening a ROM will hand this surface to the embedded gopher64 bridge."
        case .booting:
            "Cinder64 is waiting for the embedded runtime to bind to the host surface."
        case .paused:
            "Emulation is loaded and paused."
        case .running:
            "Emulation is running."
        case .failed:
            "The embedded runtime stopped. Reopen the ROM to continue."
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
        view.capturesKeyboardInput = capturesKeyboardInput
        view.pumpRuntimeEvents = pumpRuntimeEvents
        return view
    }

    func updateNSView(_ nsView: RenderSurfaceHostingView, context: Context) {
        nsView.surfaceChanged = surfaceChanged
        nsView.keyboardInputChanged = keyboardInputChanged
        nsView.capturesKeyboardInput = capturesKeyboardInput
        nsView.pumpRuntimeEvents = pumpRuntimeEvents
        nsView.publishDescriptorIfPossible()
    }
}

private final class RenderSurfaceHostingView: NSView {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.patricedery.Cinder64",
        category: "RenderSurface"
    )

    var surfaceChanged: (RenderSurfaceDescriptor?) -> Void = { _ in }
    var keyboardInputChanged: (EmbeddedKeyboardEvent) -> Void = { _ in }
    var capturesKeyboardInput = false
    var pumpRuntimeEvents: () -> Void = {}
    private var eventPumpTimer: Timer?
    private var localKeyboardEventMonitor: Any?
    private var lastPublishedDescriptor: RenderSurfaceDescriptor?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
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

    func publishDescriptorIfPossible() {
        let size = bounds.integral.size
        guard size.width > 0, size.height > 0, let window else {
            if lastPublishedDescriptor != nil {
                Self.logger.info("render-surface invalidated")
                lastPublishedDescriptor = nil
            }
            surfaceChanged(nil)
            return
        }

        // Hosted Vulkan on macOS needs a live CAMetalLayer with a drawable size
        // that tracks the NSView bounds and backing scale.
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.frame = bounds
            metalLayer.contentsScale = window.backingScaleFactor
            metalLayer.drawableSize = CGSize(
                width: size.width * window.backingScaleFactor,
                height: size.height * window.backingScaleFactor
            )
        }

        let descriptor = RenderSurfaceDescriptor(
            windowHandle: UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()),
            viewHandle: UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque()),
            width: Int(size.width),
            height: Int(size.height),
            backingScaleFactor: Double(window.backingScaleFactor)
        )
        guard descriptor != lastPublishedDescriptor else {
            return
        }

        let backingLayerDescription = layer.map { String(describing: type(of: $0)) } ?? "nil"
        let drawableSize: CGSize
        if let metalLayer = layer as? CAMetalLayer {
            drawableSize = metalLayer.drawableSize
        } else {
            drawableSize = .zero
        }
        Self.logger.info(
            "render-surface published size=\(descriptor.width)x\(descriptor.height) scale=\(descriptor.backingScaleFactor, format: .fixed(precision: 2)) layer=\(backingLayerDescription, privacy: .public) drawable=\(Int(drawableSize.width))x\(Int(drawableSize.height))"
        )
        lastPublishedDescriptor = descriptor
        surfaceChanged(descriptor)
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
        pumpRuntimeEvents()
    }
}
