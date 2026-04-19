import SwiftUI

struct SettingsView: View {
    @Bindable var session: EmulationSession
    let applyDisplayMode: (MainWindowDisplayMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Window, audio, and speed controls for the front end.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SettingsSection(
                        title: "Display",
                        subtitle: "Fixed window modes and renderer presentation."
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
                        subtitle: "Keep gameplay live or mute it entirely."
                    ) {
                        Toggle("Mute audio", isOn: binding(for: \.muteAudio))
                    }

                    SettingsSectionDivider()

                    SettingsSection(
                        title: "Performance",
                        subtitle: "Adjust emulation speed without changing the shell."
                    ) {
                        Stepper(value: binding(for: \.speedPercent), in: 25 ... 300, step: 5) {
                            LabeledContent("Speed", value: "\(session.activeSettings.speedPercent)%")
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 840, alignment: .topLeading)
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
            HStack(alignment: .top, spacing: 36) {
                summaryColumn
                    .frame(width: 240, alignment: .topLeading)
                controlColumn
            }

            VStack(alignment: .leading, spacing: 16) {
                summaryColumn
                controlColumn
            }
        }
        .padding(.vertical, 18)
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
    }
}
