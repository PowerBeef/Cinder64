import SwiftUI

struct ContentView: View {
    @Bindable var session: EmulationSession

    var body: some View {
        NavigationSplitView {
            RecentGamesListView(session: session)
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                if let banner = session.snapshot.warningBanner {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(banner.title)
                            .font(.headline)
                        Text(banner.message)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                RenderSurfaceView(
                    snapshot: session.snapshot,
                    surfaceChanged: session.updateRenderSurface,
                    keyboardInputChanged: session.handleKeyboardInput,
                    pumpRuntimeEvents: session.pumpRuntimeEvents
                )

                HStack(spacing: 16) {
                    MetricTile(title: "Runtime", value: session.snapshot.rendererName)
                    MetricTile(title: "FPS", value: session.snapshot.fps.formatted(.number.precision(.fractionLength(0))))
                    MetricTile(title: "Save Slot", value: "\(session.snapshot.activeSaveSlot)")
                    MetricTile(title: "Audio", value: session.snapshot.audioMuted ? "Muted" : "Live")
                }

                Spacer()
            }
            .padding(24)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
