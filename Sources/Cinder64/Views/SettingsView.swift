import SwiftUI

struct SettingsView: View {
    @Bindable var session: EmulationSession
    let applyDisplayMode: (MainWindowDisplayMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Display, audio, and speed controls for the current front-end experience.")
                        .foregroundStyle(.secondary)
                }

                SettingsPanel {
                    SettingsSection(
                        title: "Display",
                        subtitle: "Fixed window modes and video presentation."
                    ) {
                        Picker("Display Mode", selection: displayModeBinding) {
                            ForEach(MainWindowDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        Divider()

                        Stepper(value: binding(for: \.upscaleMultiplier), in: 1 ... 8) {
                            LabeledContent("Renderer Upscaling", value: "\(session.activeSettings.upscaleMultiplier)x")
                        }

                        Toggle("Integer scaling", isOn: binding(for: \.integerScaling))
                        Toggle("CRT filter", isOn: binding(for: \.crtFilterEnabled))
                    }

                    SettingsSectionDivider()

                    SettingsSection(
                        title: "Audio",
                        subtitle: "Keep gameplay sound live or mute it entirely."
                    ) {
                        Toggle("Mute audio", isOn: binding(for: \.muteAudio))
                    }

                    SettingsSectionDivider()

                    SettingsSection(
                        title: "Performance",
                        subtitle: "Adjust the pace of emulation without changing the shell."
                    ) {
                        Stepper(value: binding(for: \.speedPercent), in: 25 ... 300, step: 5) {
                            LabeledContent("Speed", value: "\(session.activeSettings.speedPercent)%")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.clear)
    }

    private func binding<Value>(for keyPath: WritableKeyPath<CoreUserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { session.activeSettings[keyPath: keyPath] },
            set: { newValue in
                Task {
                    var settings = session.activeSettings
                    settings[keyPath: keyPath] = newValue
                    try? await session.updateSettings(settings)
                }
            }
        )
    }

    private var displayModeBinding: Binding<MainWindowDisplayMode> {
        Binding(
            get: { MainWindowDisplayMode(settings: session.activeSettings) },
            set: { newValue in
                applyDisplayMode(newValue)
            }
        )
    }
}

private struct SettingsPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ShellPalette.line)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                summaryColumn
                    .frame(width: 220, alignment: .topLeading)
                controlColumn
            }

            VStack(alignment: .leading, spacing: 14) {
                summaryColumn
                controlColumn
            }
        }
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ShellPalette.line)
            .frame(height: 1)
            .padding(.vertical, 18)
    }
}
