import Foundation
import Testing
@testable import Cinder64

@MainActor
@Suite
struct EmulationFrontendModelTests {
    @Test func openROMIntentWaitsForCoordinatorSurfaceThenLaunchesSession() async throws {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let closeCoordinator = CloseGameCoordinator(session: session)
        let surfaceCoordinator = RenderSurfaceCoordinator(displayController: nil)
        let frontend = EmulationFrontendModel(
            session: session,
            closeGameCoordinator: closeCoordinator,
            renderSurfaceCoordinator: surfaceCoordinator
        )
        let romURL = try ROMFixture.writeROM(named: "Intent Pilot.z64", in: persistence.directory)

        let launchTask = Task { @MainActor in
            await frontend.handle(.openROM(romURL))
        }
        await yieldToQueuedTasks()

        #expect(core.events.isEmpty)

        surfaceCoordinator.publishSurface(.testSurface())
        await launchTask.value

        #expect(core.events == [.openROM(romURL), .resume])
        #expect(core.openConfigurations.last?.renderSurface == .testSurface())
        #expect(frontend.state.snapshot.emulationState == .running)
    }

    @Test func transportAndStateIntentsRouteThroughTheSession() async throws {
        let fixture = try makeFrontendFixture()

        await fixture.frontend.handle(.pause)
        await fixture.frontend.handle(.resume)
        await fixture.frontend.handle(.reset)
        await fixture.frontend.handle(.saveState(slot: 2))
        await fixture.frontend.handle(.loadState(slot: 1))

        #expect(fixture.core.events == [
            .pause,
            .resume,
            .reset,
            .setSaveSlot(2),
            .saveState,
            .loadState(1),
        ])
    }

    @Test func displayModeIntentUpdatesSettingsAndAppliesWindowMode() async throws {
        let fixture = try makeFrontendFixture()
        var appliedModes: [MainWindowDisplayMode] = []
        fixture.frontend.applyDisplayModeToWindow = { appliedModes.append($0) }

        await fixture.frontend.handle(.displayModeChanged(.windowed4x))

        #expect(appliedModes == [.windowed4x])
        #expect(fixture.frontend.state.activeSettings.windowScale == 4)
        #expect(fixture.frontend.state.activeSettings.startFullscreen == false)
        #expect(fixture.core.events == [.updateSettings(fixture.frontend.state.activeSettings)])
    }

    @Test func promptVisibilityIntentUpdatesSurfaceAndInputCoordinators() async throws {
        let fixture = try makeFrontendFixture()
        var visibility: [Bool] = []
        let surfaceCoordinator = RenderSurfaceCoordinator(
            displayController: nil,
            setDisplayContentVisible: { visibility.append($0) }
        )
        let frontend = EmulationFrontendModel(
            session: fixture.session,
            closeGameCoordinator: fixture.closeCoordinator,
            renderSurfaceCoordinator: surfaceCoordinator,
            inputCoordinator: fixture.inputCoordinator
        )

        await frontend.handle(.promptVisibilityChanged(true))
        await frontend.handle(.promptVisibilityChanged(false))

        #expect(visibility == [false, true])
        #expect(fixture.releaseCount == 1)
    }

    private func makeFrontendFixture() throws -> FrontendFixture {
        let persistence = try PersistenceFixture()
        let core = CoreHostSpy()
        let session = EmulationSession(coreHost: core, persistenceStore: persistence.persistence)
        let closeCoordinator = CloseGameCoordinator(session: session)
        let inputCoordinator = GameplayInputCoordinator(
            addLocalMonitor: { _, handler in handler as Any },
            removeMonitor: { _ in },
            notificationCenter: NotificationCenter(),
            appActiveProvider: { true },
            eventWindowMatcher: { _, _ in true }
        )
        var releaseCount = 0
        inputCoordinator.install(
            eventHandler: { _ in },
            releaseHeldInput: { releaseCount += 1 },
            emulationState: { EmulationState.running },
            hasVisiblePrompt: { false }
        )
        let frontend = EmulationFrontendModel(
            session: session,
            closeGameCoordinator: closeCoordinator,
            renderSurfaceCoordinator: RenderSurfaceCoordinator(displayController: nil),
            inputCoordinator: inputCoordinator
        )
        return FrontendFixture(
            persistence: persistence,
            core: core,
            session: session,
            closeCoordinator: closeCoordinator,
            inputCoordinator: inputCoordinator,
            frontend: frontend,
            releaseCount: { releaseCount }
        )
    }
}

@MainActor
private struct FrontendFixture {
    let persistence: PersistenceFixture
    let core: CoreHostSpy
    let session: EmulationSession
    let closeCoordinator: CloseGameCoordinator
    let inputCoordinator: GameplayInputCoordinator
    let frontend: EmulationFrontendModel
    private let releaseCountProvider: () -> Int

    init(
        persistence: PersistenceFixture,
        core: CoreHostSpy,
        session: EmulationSession,
        closeCoordinator: CloseGameCoordinator,
        inputCoordinator: GameplayInputCoordinator,
        frontend: EmulationFrontendModel,
        releaseCount: @escaping () -> Int
    ) {
        self.persistence = persistence
        self.core = core
        self.session = session
        self.closeCoordinator = closeCoordinator
        self.inputCoordinator = inputCoordinator
        self.frontend = frontend
        self.releaseCountProvider = releaseCount
    }

    var releaseCount: Int {
        releaseCountProvider()
    }
}
