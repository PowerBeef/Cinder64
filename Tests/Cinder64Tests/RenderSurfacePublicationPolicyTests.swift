import Testing
@testable import Cinder64

struct RenderSurfacePublicationPolicyTests {
    @Test func unchangedGeometryDoesNotRepublish() {
        let committed = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 3
        )

        let decision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: committed,
            isLiveResize: false
        )

        #expect(decision == .noChange)
    }

    @Test func liveResizeCoalescesIntoOneCommittedUpdate() {
        let committed = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 3
        )
        let resized = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 700,
            logicalHeight: 500,
            pixelWidth: 1400,
            pixelHeight: 1000,
            backingScaleFactor: 2,
            revision: 4
        )

        let heldDecision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: resized,
            isLiveResize: true
        )
        let commitDecision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: resized,
            isLiveResize: false
        )

        #expect(heldDecision == .defer(resized))
        #expect(commitDecision == .publish(resized, kind: .resize))
    }

    @Test func handleChangeForcesReattach() {
        let committed = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 3
        )
        let reattached = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 2,
            windowHandle: 0xFACE,
            viewHandle: 0xD00D,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 4
        )

        let decision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: reattached,
            isLiveResize: false
        )

        #expect(decision == .publish(reattached, kind: .reattach))
    }

    @Test func scaleChangeUsesResizeInsteadOfReattach() {
        let committed = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 3
        )
        let rescaled = RenderSurfaceDescriptor(
            surfaceID: 1,
            generation: 1,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1920,
            pixelHeight: 1440,
            backingScaleFactor: 3,
            revision: 4
        )

        let decision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: rescaled,
            isLiveResize: false
        )

        #expect(decision == .publish(rescaled, kind: .resize))
    }

    @Test func generationChangeForcesReattachEvenIfHandlesStayTheSame() {
        let committed = RenderSurfaceDescriptor(
            surfaceID: 7,
            generation: 3,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 3
        )
        let replacement = RenderSurfaceDescriptor(
            surfaceID: 7,
            generation: 4,
            windowHandle: 0xCAFE,
            viewHandle: 0xBEEF,
            logicalWidth: 640,
            logicalHeight: 480,
            pixelWidth: 1280,
            pixelHeight: 960,
            backingScaleFactor: 2,
            revision: 1
        )

        let decision = RenderSurfacePublicationPolicy.decide(
            previousCommitted: committed,
            proposed: replacement,
            isLiveResize: false
        )

        #expect(decision == .publish(replacement, kind: .reattach))
    }
}
