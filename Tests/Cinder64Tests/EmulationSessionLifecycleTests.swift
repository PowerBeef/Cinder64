import Foundation
import Testing
@testable import Cinder64

@MainActor
@Suite
struct EmulationSessionLifecycleTests {
    @Test func lifecycleStartsStopped() throws {
        let persistence = try PersistenceFixture(prefix: "cinder64-lifecycle")
        let session = EmulationSession(
            coreHost: CoreHostSpy(),
            persistenceStore: persistence.persistence
        )

        #expect(session.lifecycleState == RuntimeLifecycleState.stopped)
    }

    @Test func openingAROMTransitionsThroughBootingReadyPausedRunning() async throws {
        let persistence = try PersistenceFixture(prefix: "cinder64-lifecycle")
        let core = CoreHostSpy()
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: persistence.persistence
        )
        let romURL = try ROMFixture.writeROM(named: "Pilotwings 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)

        #expect(session.lifecycleState == RuntimeLifecycleState.running)
        #expect(core.recordedLifecycleStates == [.booting, .readyPaused, .running])
    }

    @Test func stopTransitionsThroughStoppingToStopped() async throws {
        let persistence = try PersistenceFixture(prefix: "cinder64-lifecycle")
        let session = EmulationSession(
            coreHost: CoreHostSpy(),
            persistenceStore: persistence.persistence
        )
        let romURL = try ROMFixture.writeROM(named: "Extreme-G.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        try await session.stop()

        #expect(session.lifecycleState == RuntimeLifecycleState.stopped)
    }

    @Test func stopSwallowsShutdownErrorAndSurfacesWarningBanner() async throws {
        let persistence = try PersistenceFixture(prefix: "cinder64-lifecycle")
        let core = CoreHostSpy()
        core.stopError = NSError(
            domain: "test",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "simulated MoltenVK wedge"]
        )
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: persistence.persistence
        )
        let romURL = try ROMFixture.writeROM(named: "Lylat Wars.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        try await session.stop()

        #expect(session.lifecycleState == RuntimeLifecycleState.stopped)
        #expect(session.snapshot.emulationState == .stopped)
        #expect(session.snapshot.activeROM == nil)
        #expect(session.snapshot.warningBanner?.title == "Emulator shutdown timed out")
    }

    @Test func runtimeFailureTransitionsToFailed() async throws {
        let persistence = try PersistenceFixture(prefix: "cinder64-lifecycle")
        let core = CoreHostSpy()
        let session = EmulationSession(
            coreHost: core,
            persistenceStore: persistence.persistence
        )
        let romURL = try ROMFixture.writeROM(named: "Wave Race 64.z64", in: persistence.directory)
        session.updateRenderSurface(.testSurface())

        try await session.openROM(url: romURL)
        core.nextPumpEvent = .runtimeTerminated("runtime crashed")
        session.pumpRuntimeEvents()
        await yieldToQueuedTasks()

        #expect(session.lifecycleState == RuntimeLifecycleState.failed)
    }
}

extension RenderSurfaceDescriptor {
    static func testSurface(
        windowHandle: UInt = 0xABCDABCD,
        viewHandle: UInt = 0xFACADE,
        width: Int = 1280,
        height: Int = 720,
        backingScaleFactor: Double = 2
    ) -> RenderSurfaceDescriptor {
        RenderSurfaceDescriptor(
            windowHandle: windowHandle,
            viewHandle: viewHandle,
            width: width,
            height: height,
            backingScaleFactor: backingScaleFactor
        )
    }
}

@MainActor
func yieldToQueuedTasks(count: Int = 3) async {
    for _ in 0..<count {
        await Task.yield()
    }
}

@MainActor
func waitForCondition(
    _ description: String,
    timeoutIterations: Int = 1_000,
    condition: () -> Bool
) async {
    for _ in 0..<timeoutIterations {
        if condition() {
            return
        }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(description)")
}
