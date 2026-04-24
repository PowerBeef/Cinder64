import SwiftUI

private struct PromptBackdrop: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.18))
                .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

private struct PromptOverlayContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            PromptBackdrop()

            content
                .frame(maxWidth: 430)
                .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CloseGamePromptCard: View {
    let prompt: CloseGamePromptState
    let cancelRequested: () -> Void
    let closeWithoutSavingRequested: () -> Void
    let saveAndCloseRequested: () -> Void

    private var isBusy: Bool {
        prompt.phase == .saving || prompt.phase == .closing
    }

    private var message: String {
        if let errorMessage = prompt.errorMessage, errorMessage.isEmpty == false {
            return errorMessage
        }

        if prompt.canSave {
            return "Save a protected close-game checkpoint before leaving \(prompt.romDisplayName), or leave without saving."
        }

        return "This session cannot be saved right now, but you can still leave the game or cancel."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Close Game")
                    .font(.title2.weight(.semibold))

                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text(prompt.phase == .saving ? "Saving protected close-game slot…" : "Closing game…")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: cancelRequested)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isBusy)

                Spacer(minLength: 0)

                Button("Close Without Saving", action: closeWithoutSavingRequested)
                    .disabled(isBusy)

                Button("Save & Close", action: saveAndCloseRequested)
                    .buttonStyle(.borderedProminent)
                    .tint(ShellPalette.accent)
                    .disabled(prompt.canSave == false || isBusy)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 10)
    }
}

struct ResumeProtectedSavePromptCard: View {
    let prompt: ResumeProtectedSavePromptState
    let continueRequested: () -> Void
    let startFreshRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Resume Previous Session?")
                    .font(.title2.weight(.semibold))

                Text("A protected close-game save is available for \(prompt.romDisplayName). Continue from that checkpoint or start a fresh launch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                Button("Start Fresh", action: startFreshRequested)

                Button("Continue", action: continueRequested)
                    .buttonStyle(.borderedProminent)
                    .tint(ShellPalette.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(ShellPalette.strongLine)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 22, y: 10)
    }
}
