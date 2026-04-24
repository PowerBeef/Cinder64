import SwiftUI

struct SessionStatePill: View {
    let snapshot: SessionSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tintColor)
                .frame(width: 6, height: 6)

            Text(SessionToolbarPresentation.statusTitle(for: snapshot))
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ShellPalette.accentGlow, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tintColor.opacity(0.2))
        }
    }

    private var tintColor: Color {
        switch snapshot.emulationState {
        case .running:
            ShellPalette.accent
        case .paused:
            Color.orange.opacity(0.78)
        case .booting:
            ShellPalette.accent.opacity(0.82)
        case .failed:
            Color.red.opacity(0.82)
        case .stopped:
            .secondary
        }
    }
}

struct WarningBannerBar: View {
    let banner: WarningBanner
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ShellPalette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(banner.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss warning")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ShellPalette.line)
        }
    }
}

struct SessionStatusStrip: View {
    let items: [SessionStatusItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SessionStatusInlineItem(item: item)

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(ShellPalette.line)
                            .frame(width: 1, height: 14)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    SessionStatusInlineItem(item: item)
                }
            }
        }
    }
}

private struct SessionStatusInlineItem: View {
    let item: SessionStatusItem

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.symbolName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 11)

            Text(item.label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            Text(item.value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }
}
