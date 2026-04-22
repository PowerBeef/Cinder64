import SwiftUI

/// Floating card rendered above the emulator's Metal frame to communicate
/// non-running states (booting, paused, failed). Hosted inside the
/// EmulatorDisplayWindow via NSHostingView so it composites above the
/// Vulkan frame reliably.
struct SurfaceOverlayCard: View {
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
