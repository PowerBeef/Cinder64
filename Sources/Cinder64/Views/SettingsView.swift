import SwiftUI

struct SettingsView: View {
    @Bindable var session: EmulationSession

    var body: some View {
        Form {
            Section("Video") {
                Toggle("Start in fullscreen", isOn: binding(for: \.startFullscreen))
                Stepper(value: binding(for: \.upscaleMultiplier), in: 1 ... 8) {
                    LabeledContent("Upscaling", value: "\(session.activeSettings.upscaleMultiplier)x")
                }
                Toggle("Integer scaling", isOn: binding(for: \.integerScaling))
                Toggle("CRT filter", isOn: binding(for: \.crtFilterEnabled))
            }

            Section("Audio & Speed") {
                Toggle("Mute audio", isOn: binding(for: \.muteAudio))
                Stepper(value: binding(for: \.speedPercent), in: 25 ... 300, step: 5) {
                    LabeledContent("Speed", value: "\(session.activeSettings.speedPercent)%")
                }
            }
        }
        .formStyle(.grouped)
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
}
