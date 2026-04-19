import Foundation
import Testing
@testable import Cinder64

struct Cinder64PresentationTests {
    @Test func mainWindowLaunchUsesAFreshLauncherRestorationPolicy() {
        #expect(MainWindowLaunchPresentation.restoresPreviousWindowState == false)
    }

    @Test func stoppedSessionsUseTheHomeDashboardShell() {
        #expect(ShellPresentation.mode(for: .idle) == .homeDashboard)
    }

    @Test func homeDashboardUsesVisibleWindowChrome() {
        let configuration = MainWindowChromePresentation.configuration(for: .homeDashboard)

        #expect(configuration.showsVisibleTitle)
        #expect(configuration.usesUnifiedCompactToolbar == false)
    }

    @Test func bootingSessionsUseTheGameplayShell() {
        let snapshot = SessionSnapshot(
            emulationState: .booting,
            activeROM: makeIdentity(name: "Super Mario 64"),
            rendererName: "gopher64",
            fps: 0,
            videoMode: .none,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )

        #expect(ShellPresentation.mode(for: snapshot) == .gameplay)
    }

    @Test func gameplayUsesCompactPlayerChrome() {
        let configuration = MainWindowChromePresentation.configuration(for: .gameplay)

        #expect(configuration.showsVisibleTitle == false)
        #expect(configuration.usesUnifiedCompactToolbar)
    }

    @Test func appReopenKeepsCurrentWindowStateWhenAWindowIsAlreadyVisible() {
        #expect(
            AppReopenPresentation.action(
                hasVisibleWindows: true,
                hasTrackedMainWindow: true
            ) == .keepCurrentWindowState
        )
    }

    @Test func appReopenShowsTheTrackedMainWindowWhenNoneAreVisible() {
        #expect(
            AppReopenPresentation.action(
                hasVisibleWindows: false,
                hasTrackedMainWindow: true
            ) == .showTrackedWindow
        )
    }

    @Test func appReopenFallsBackToSystemWindowReopenWhenNoMainWindowIsTracked() {
        #expect(
            AppReopenPresentation.action(
                hasVisibleWindows: false,
                hasTrackedMainWindow: false
            ) == .allowSystemWindowReopen
        )
    }

    @Test func stoppedSessionsDoNotShowASurfaceOverlay() {
        #expect(SurfaceOverlayPresentation.content(for: .idle) == nil)
    }

    @Test func pausedSessionsEnableResumeAndResetButNotPause() {
        let snapshot = SessionSnapshot(
            emulationState: .paused,
            activeROM: makeIdentity(name: "Star Fox 64"),
            rendererName: "gopher64",
            fps: 0,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )

        let availability = SessionToolbarPresentation.actionAvailability(for: snapshot)

        #expect(availability.canPause == false)
        #expect(availability.canResume)
        #expect(availability.canReset)
        #expect(availability.canUseStateMenu)
        #expect(availability.canToggleAudio)
    }

    @Test func bootingSessionsDisableRuntimeToolsUntilReady() {
        let snapshot = SessionSnapshot(
            emulationState: .booting,
            activeROM: makeIdentity(name: "Star Fox 64"),
            rendererName: "gopher64",
            fps: 0,
            videoMode: .none,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: nil
        )

        let availability = SessionToolbarPresentation.actionAvailability(for: snapshot)

        #expect(availability.canPause == false)
        #expect(availability.canResume == false)
        #expect(availability.canReset == false)
        #expect(availability.canUseStateMenu == false)
        #expect(availability.canToggleAudio == false)
    }

    @Test func failedSessionsDisableRuntimeToolsButKeepPlayerChrome() {
        let snapshot = SessionSnapshot(
            emulationState: .failed,
            activeROM: makeIdentity(name: "Star Fox 64"),
            rendererName: "gopher64",
            fps: 0,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 0,
            warningBanner: WarningBanner(title: "Stopped", message: "The runtime exited.")
        )

        let availability = SessionToolbarPresentation.actionAvailability(for: snapshot)

        #expect(availability.canPause == false)
        #expect(availability.canResume == false)
        #expect(availability.canReset == false)
        #expect(availability.canUseStateMenu == false)
        #expect(availability.canToggleAudio == false)
    }

    @Test func runningSessionsUseSlimChromeCopy() {
        let snapshot = SessionSnapshot(
            emulationState: .running,
            activeROM: makeIdentity(name: "Wave Race 64"),
            rendererName: "gopher64",
            fps: 60,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 2,
            warningBanner: nil
        )

        #expect(SessionToolbarPresentation.subtitle(for: snapshot) == nil)
    }

    @Test func stateMenuUsesHumanReadableSlotLabels() {
        #expect(SessionToolbarPresentation.stateMenuTitle(forSlot: 0) == "State • Slot 1")
        #expect(SessionToolbarPresentation.stateMenuTitle(forSlot: 3) == "State • Slot 4")
    }

    @Test func gameplayToolbarUsesHomeActionCopy() {
        #expect(SessionToolbarPresentation.homeActionTitle == "Home")
        #expect(SessionToolbarPresentation.homeActionSymbolName == "house")
    }

    @Test func sessionConsoleAudioToolReflectsMuteState() {
        let liveAudioSnapshot = SessionSnapshot(
            emulationState: .running,
            activeROM: makeIdentity(name: "Wave Race 64"),
            rendererName: "Fake Renderer",
            fps: 57.9,
            videoMode: .windowed,
            audioMuted: false,
            activeSaveSlot: 1,
            warningBanner: nil
        )
        let mutedAudioSnapshot = SessionSnapshot(
            emulationState: .running,
            activeROM: makeIdentity(name: "Wave Race 64"),
            rendererName: "Fake Renderer",
            fps: 57.9,
            videoMode: .windowed,
            audioMuted: true,
            activeSaveSlot: 1,
            warningBanner: nil
        )

        #expect(SessionToolbarPresentation.audioToolTitle(for: liveAudioSnapshot) == "Mute")
        #expect(SessionToolbarPresentation.audioToolSymbolName(for: liveAudioSnapshot) == "speaker.wave.2")
        #expect(SessionToolbarPresentation.audioToolTitle(for: mutedAudioSnapshot) == "Unmute")
        #expect(SessionToolbarPresentation.audioToolSymbolName(for: mutedAudioSnapshot) == "speaker.slash")
    }

    @Test func statusStripOnlyIncludesPassiveVideoState() {
        let snapshot = SessionSnapshot(
            emulationState: .running,
            activeROM: makeIdentity(name: "Wave Race 64"),
            rendererName: "Fake Renderer",
            fps: 57.9,
            videoMode: .windowed,
            audioMuted: true,
            activeSaveSlot: 3,
            warningBanner: nil
        )

        let items = SessionStatusStripPresentation.items(for: snapshot, displayMode: .windowed3x)

        #expect(items.count == 1)
        #expect(items.contains(SessionStatusItem(label: "Video", value: "Fake Renderer • 58 FPS", symbolName: "display")))
    }

    @Test func homeDashboardSummarizesRecentGames() {
        let content = HomeDashboardPresentation.content(
            for: [
                RecentGameRecord(identity: makeIdentity(name: "Pilotwings 64"), lastOpenedAt: .now),
                RecentGameRecord(identity: makeIdentity(name: "Mario Kart 64"), lastOpenedAt: .now),
            ]
        )

        #expect(content.title == "Cinder64")
        #expect(content.recentSummary == "2 launches ready.")
    }

    @Test func homeDashboardHandlesAnEmptyRecentList() {
        let content = HomeDashboardPresentation.content(for: [])

        #expect(content.recentSummary == "No recent launches.")
        #expect(content.primaryActionTitle == "Open ROM…")
    }

    @Test func recentGameRecencyFormatterUsesTodayAndYesterdayLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_713_441_600)

        let today = now.addingTimeInterval(-60 * 60)
        let yesterday = now.addingTimeInterval(-60 * 60 * 24)

        #expect(RecentGameRecencyFormatter.label(for: today, now: now, calendar: calendar) == "Today")
        #expect(RecentGameRecencyFormatter.label(for: yesterday, now: now, calendar: calendar) == "Yesterday")
    }

    private func makeIdentity(name: String) -> ROMIdentity {
        ROMIdentity(
            id: "rom-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            fileURL: URL(fileURLWithPath: "/tmp/\(name).z64"),
            displayName: name,
            sha256: "abc123"
        )
    }
}
