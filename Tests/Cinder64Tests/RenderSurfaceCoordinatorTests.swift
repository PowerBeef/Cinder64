import Testing
@testable import Cinder64

@MainActor
@Suite
struct RenderSurfaceCoordinatorTests {
    @Test func validSurfaceResumesWaiterAndPublishesDescriptor() async throws {
        var publishedSurfaces: [RenderSurfaceDescriptor?] = []
        let coordinator = RenderSurfaceCoordinator(
            displayController: nil,
            onSurfaceChanged: { publishedSurfaces.append($0) }
        )
        let surface = RenderSurfaceDescriptor.testSurface()

        let waitTask = Task { @MainActor in
            try await coordinator.waitForValidSurface(timeout: .seconds(1))
        }
        await yieldToQueuedTasks()

        coordinator.publishSurface(surface)

        let resolvedSurface = try await waitTask.value
        #expect(resolvedSurface == surface)
        #expect(publishedSurfaces == [surface])
    }

    @Test func missingSurfaceTimesOutAndLatePublicationDoesNotResumeStaleWork() async throws {
        let coordinator = RenderSurfaceCoordinator(displayController: nil)

        await #expect(throws: EmulationSessionError.renderSurfaceUnavailable) {
            try await coordinator.waitForValidSurface(timeout: .milliseconds(10))
        }

        coordinator.publishSurface(.testSurface())

        let resolvedSurface = try await coordinator.waitForValidSurface(timeout: .milliseconds(10))
        #expect(resolvedSurface == .testSurface())
    }

    @Test func promptVisibilityHidesAndRestoresDisplayContent() {
        var contentVisibility: [Bool] = []
        let coordinator = RenderSurfaceCoordinator(
            displayController: nil,
            setDisplayContentVisible: { contentVisibility.append($0) }
        )

        coordinator.setPromptVisible(true)
        coordinator.setPromptVisible(false)

        #expect(contentVisibility == [false, true])
    }
}
