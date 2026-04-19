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

enum MainWindowLaunchPresentation {
    static let restoresPreviousWindowState = false
}

enum AppReopenAction: Equatable, Sendable {
    case keepCurrentWindowState
    case showTrackedWindow
    case allowSystemWindowReopen
}

enum AppReopenPresentation {
    static func action(hasVisibleWindows: Bool, hasTrackedMainWindow: Bool) -> AppReopenAction {
        if hasVisibleWindows {
            .keepCurrentWindowState
        } else if hasTrackedMainWindow {
            .showTrackedWindow
        } else {
            .allowSystemWindowReopen
        }
    }
}

enum MainWindowChromeMode: Equatable, Sendable {
    case homeDashboard
    case gameplay

    init(shellMode: ShellPresentationMode) {
        switch shellMode {
        case .homeDashboard:
            self = .homeDashboard
        case .gameplay:
            self = .gameplay
        }
    }
}

struct MainWindowChromeConfiguration: Equatable, Sendable {
    let showsVisibleTitle: Bool
    let usesUnifiedCompactToolbar: Bool
}

enum MainWindowChromePresentation {
    static func configuration(for mode: MainWindowChromeMode) -> MainWindowChromeConfiguration {
        switch mode {
        case .homeDashboard:
            MainWindowChromeConfiguration(
                showsVisibleTitle: true,
                usesUnifiedCompactToolbar: false
            )
        case .gameplay:
            MainWindowChromeConfiguration(
                showsVisibleTitle: false,
                usesUnifiedCompactToolbar: true
            )
        }
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
            eyebrow: "Nintendo 64 for macOS",
            title: "Cinder64",
            message: "Launch a ROM and let the window become the console.",
            recentSummary: recentSummary(for: recentGames.count),
            primaryActionTitle: "Open ROM…"
        )
    }

    private static func recentSummary(for count: Int) -> String {
        switch count {
        case 0:
            "No recent launches."
        case 1:
            "1 launch ready."
        default:
            "\(count) launches ready."
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
                title: snapshot.activeROM?.displayName ?? "Starting",
                message: "Preparing the stage and the embedded runtime.",
                tone: .info
            )
        case .paused:
            SurfaceOverlayContent(
                symbolName: "pause.circle",
                title: snapshot.activeROM?.displayName ?? "Paused",
                message: "Resume when you are ready to continue.",
                tone: .warning
            )
        case .failed:
            SurfaceOverlayContent(
                symbolName: "exclamationmark.triangle",
                title: "Session Stopped",
                message: snapshot.warningBanner?.message ?? "The embedded runtime exited unexpectedly.",
                tone: .critical
            )
        }
    }
}

struct SessionToolbarActionAvailability: Equatable, Sendable {
    let canPause: Bool
    let canResume: Bool
    let canReset: Bool
    let canUseStateMenu: Bool
    let canToggleAudio: Bool
}

enum SessionToolbarPresentation {
    static let homeActionTitle = "Home"
    static let homeActionSymbolName = "house"

    static func title(for snapshot: SessionSnapshot) -> String {
        snapshot.activeROM?.displayName ?? "Cinder64"
    }

    static func subtitle(for snapshot: SessionSnapshot) -> String? {
        nil
    }

    static func actionAvailability(for snapshot: SessionSnapshot) -> SessionToolbarActionAvailability {
        let runtimeToolsEnabled = snapshot.emulationState == .running || snapshot.emulationState == .paused

        return SessionToolbarActionAvailability(
            canPause: snapshot.emulationState == .running,
            canResume: snapshot.emulationState == .paused,
            canReset: runtimeToolsEnabled,
            canUseStateMenu: runtimeToolsEnabled,
            canToggleAudio: runtimeToolsEnabled
        )
    }

    static func transportTitle(for snapshot: SessionSnapshot) -> String {
        snapshot.emulationState == .paused ? "Resume" : "Pause"
    }

    static func transportSymbolName(for snapshot: SessionSnapshot) -> String {
        snapshot.emulationState == .paused ? "play.fill" : "pause.fill"
    }

    static func stateMenuTitle(forSlot slot: Int) -> String {
        "State • Slot \(slot + 1)"
    }

    static func audioToolTitle(for snapshot: SessionSnapshot) -> String {
        snapshot.audioMuted ? "Unmute" : "Mute"
    }

    static func audioToolSymbolName(for snapshot: SessionSnapshot) -> String {
        snapshot.audioMuted ? "speaker.slash" : "speaker.wave.2"
    }

    static func compactDisplayTitle(for displayMode: MainWindowDisplayMode) -> String {
        switch displayMode {
        case .windowed1x:
            "1x"
        case .windowed2x:
            "2x"
        case .windowed3x:
            "3x"
        case .windowed4x:
            "4x"
        case .fullscreen:
            "Full"
        }
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
                label: "Video",
                value: "\(snapshot.rendererName) • \(snapshot.fps.formatted(.number.precision(.fractionLength(0)))) FPS",
                symbolName: "display"
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
