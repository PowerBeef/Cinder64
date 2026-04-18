import Foundation
import Testing
@testable import Cinder64

struct Cinder64PresentationTests {
    @Test func stoppedSessionsUseTheHomeDashboardShell() {
        #expect(ShellPresentation.mode(for: .idle) == .homeDashboard)
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

    @Test func statusStripIncludesDisplayModeAndAudioState() {
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

        #expect(items.contains(SessionStatusItem(label: "Video", value: "Fake Renderer • 58 FPS", symbolName: "display")))
        #expect(items.contains(SessionStatusItem(label: "Window", value: "3x Windowed", symbolName: "rectangle.inset.filled")))
        #expect(items.contains(SessionStatusItem(label: "Audio", value: "Muted", symbolName: "speaker.slash")))
    }

    @Test func homeDashboardSummarizesRecentGames() {
        let content = HomeDashboardPresentation.content(
            for: [
                RecentGameRecord(identity: makeIdentity(name: "Pilotwings 64"), lastOpenedAt: .now),
                RecentGameRecord(identity: makeIdentity(name: "Mario Kart 64"), lastOpenedAt: .now),
            ]
        )

        #expect(content.title == "Cinder64")
        #expect(content.recentSummary == "2 recent launches ready.")
    }

    @Test func homeDashboardHandlesAnEmptyRecentList() {
        let content = HomeDashboardPresentation.content(for: [])

        #expect(content.recentSummary == "No recent launches yet.")
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
