import AppKit
import QuartzCore
import SwiftUI

/// Gameplay stage frame. Hosts the anchor that the
/// `EmulatorDisplayController` tracks — the actual Metal surface lives in
/// a dedicated child NSWindow, so this SwiftUI tree stays clean of
/// SDL/MoltenVK side effects and sheets/alerts presented on the main
/// window work correctly.
///
/// Surface publication and pump ticks are mediated by
/// `RenderSurfaceCoordinator`, so the view only hosts the anchor and
/// presentation shell.
struct RenderSurfaceView: View {
    let snapshot: SessionSnapshot
    let coordinator: RenderSurfaceCoordinator

    var body: some View {
        if let controller = coordinator.displayController {
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
                coordinator.wireSurfaceCallbacks()
                coordinator.updateOverlay(for: snapshot)
            }
            .onChange(of: snapshot) { _, newValue in
                coordinator.updateOverlay(for: newValue)
            }
        }
    }
}
