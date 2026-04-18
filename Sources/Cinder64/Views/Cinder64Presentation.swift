import Foundation

enum ShellPresentationMode: Equatable, Sendable {
    case homeDashboard
    case gameplay
}

enum ShellPresentation {
    static func mode(for snapshot: SessionSnapshot) -> ShellPresentationMode {
        snapshot.emulationState == .stopped ? .homeDashboard : .gameplay
    }
}

struct HomeDashboardContent: Equatable, Sendable {
    let eyebrow: String
    let title: String
    let message: String
    let recentSummary: String
    let primaryActionTitle: String
}

enum HomeDashboardPresentation {
    static func content(for recentGames: [RecentGameRecord]) -> HomeDashboardContent {
        HomeDashboardContent(
            eyebrow: "Native macOS Nintendo 64 Front End",
            title: "Cinder64",
            message: "Open a ROM, relaunch a recent favorite, and let gameplay take over the window.",
            recentSummary: recentSummary(for: recentGames.count),
            primaryActionTitle: "Open ROM…"
        )
    }

    private static func recentSummary(for count: Int) -> String {
        switch count {
        case 0:
            "No recent launches yet."
        case 1:
            "1 recent launch ready."
        default:
            "\(count) recent launches ready."
        }
    }
}

enum SurfaceOverlayTone: Equatable, Sendable {
    case info
    case warning
    case critical
}

struct SurfaceOverlayContent: Equatable, Sendable {
    let symbolName: String
    let title: String
    let message: String
    let tone: SurfaceOverlayTone
}

enum SurfaceOverlayPresentation {
    static func content(for snapshot: SessionSnapshot) -> SurfaceOverlayContent? {
        switch snapshot.emulationState {
        case .stopped, .running:
            nil
        case .booting:
            SurfaceOverlayContent(
                symbolName: "arrow.triangle.2.circlepath.circle",
                title: snapshot.activeROM?.displayName ?? "Starting Session",
                message: "Preparing video, input, and the embedded runtime.",
                tone: .info
            )
        case .paused:
            SurfaceOverlayContent(
                symbolName: "pause.circle",
                title: snapshot.activeROM?.displayName ?? "Paused",
                message: "Resume or reset when you are ready to continue.",
                tone: .warning
            )
        case .failed:
            SurfaceOverlayContent(
                symbolName: "exclamationmark.triangle",
                title: "Session Stopped",
                message: snapshot.warningBanner?.message ?? "The embedded runtime exited unexpectedly. Reopen the ROM to continue.",
                tone: .critical
            )
        }
    }
}

struct SessionToolbarActionAvailability: Equatable, Sendable {
    let canPause: Bool
    let canResume: Bool
    let canReset: Bool
}

enum SessionToolbarPresentation {
    static func title(for snapshot: SessionSnapshot) -> String {
        snapshot.activeROM?.displayName ?? "Cinder64"
    }

    static func subtitle(for snapshot: SessionSnapshot) -> String? {
        switch snapshot.emulationState {
        case .stopped, .running:
            nil
        case .booting:
            "Preparing video, input, and the embedded runtime."
        case .paused:
            "Paused. Resume or reset when you are ready."
        case .failed:
            snapshot.warningBanner?.message ?? "The current session stopped unexpectedly. Reopen the ROM to continue."
        }
    }

    static func actionAvailability(for snapshot: SessionSnapshot) -> SessionToolbarActionAvailability {
        SessionToolbarActionAvailability(
            canPause: snapshot.emulationState == .running,
            canResume: snapshot.emulationState == .paused,
            canReset: snapshot.emulationState == .running || snapshot.emulationState == .paused
        )
    }

    static func transportTitle(for snapshot: SessionSnapshot) -> String {
        snapshot.emulationState == .paused ? "Resume" : "Pause"
    }

    static func transportSymbolName(for snapshot: SessionSnapshot) -> String {
        snapshot.emulationState == .paused ? "play.fill" : "pause.fill"
    }

    static func statusTitle(for snapshot: SessionSnapshot) -> String {
        switch snapshot.emulationState {
        case .stopped:
            "Ready"
        case .booting:
            "Booting"
        case .paused:
            "Paused"
        case .running:
            "Running"
        case .failed:
            "Needs Attention"
        }
    }

    static func statusSymbolName(for snapshot: SessionSnapshot) -> String {
        switch snapshot.emulationState {
        case .stopped:
            "circle.dashed"
        case .booting:
            "arrow.triangle.2.circlepath"
        case .paused:
            "pause.circle.fill"
        case .running:
            "play.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

struct SessionStatusItem: Equatable, Identifiable, Sendable {
    let label: String
    let value: String
    let symbolName: String

    var id: String {
        label
    }
}

enum SessionStatusStripPresentation {
    static func items(for snapshot: SessionSnapshot, displayMode: MainWindowDisplayMode) -> [SessionStatusItem] {
        [
            SessionStatusItem(
                label: "State",
                value: SessionToolbarPresentation.statusTitle(for: snapshot),
                symbolName: SessionToolbarPresentation.statusSymbolName(for: snapshot)
            ),
            SessionStatusItem(
                label: "Video",
                value: "\(snapshot.rendererName) • \(snapshot.fps.formatted(.number.precision(.fractionLength(0)))) FPS",
                symbolName: "display"
            ),
            SessionStatusItem(
                label: "Audio",
                value: snapshot.audioMuted ? "Muted" : "Live",
                symbolName: snapshot.audioMuted ? "speaker.slash" : "speaker.wave.2"
            ),
            SessionStatusItem(
                label: "Window",
                value: displayMode.title,
                symbolName: "rectangle.inset.filled"
            ),
        ]
    }
}

enum RecentGameRecencyFormatter {
    static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
