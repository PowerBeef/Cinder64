import AppKit
import QuartzCore
import SwiftUI

/// Gameplay stage frame. Hosts the anchor that the
/// `EmulatorDisplayController` tracks — the actual Metal surface lives in
/// a dedicated child NSWindow, so this SwiftUI tree stays clean of
/// SDL/MoltenVK side effects and sheets/alerts presented on the main
/// window work correctly.
///
/// Callbacks (surface publication, pump) are wired directly
/// onto `controller.surfaceView` so the child window's NSView is the
/// single source of truth for per-session output plumbing.
struct RenderSurfaceView: View {
    let snapshot: SessionSnapshot
    let controller: EmulatorDisplayController
    let surfaceChanged: (RenderSurfaceDescriptor?) -> Void
    let pumpRuntimeEvents: () -> Void

    var body: some View {
        EmulatorDisplayAnchorView(controller: controller)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(ShellPalette.strongLine)
            }
            .frame(minHeight: 320)
            .background(ShellPalette.offBlack, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: ShellPalette.stageShadow, radius: 18, y: 8)
            .onAppear {
                wireSurfaceCallbacks()
                controller.updateOverlay(for: snapshot)
            }
            .onChange(of: snapshot) { _, newValue in
                controller.updateOverlay(for: newValue)
            }
    }

    private func wireSurfaceCallbacks() {
        let surfaceView = controller.surfaceView
        surfaceView.surfaceChanged = surfaceChanged
        surfaceView.pumpRuntimeEvents = pumpRuntimeEvents
    }
}
