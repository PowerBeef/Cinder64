import Testing
@testable import Cinder64

struct RenderSurfaceKeyboardFocusPolicyTests {
    @Test func requestsFocusWhenKeyboardCaptureBecomesActive() {
        #expect(
            RenderSurfaceKeyboardFocusPolicy.shouldRefocus(
                previousCapturesKeyboardInput: false,
                currentCapturesKeyboardInput: true
            )
        )
    }

    @Test func doesNotRequestFocusWhenKeyboardCaptureWasAlreadyActive() {
        #expect(
            RenderSurfaceKeyboardFocusPolicy.shouldRefocus(
                previousCapturesKeyboardInput: true,
                currentCapturesKeyboardInput: true
            ) == false
        )
    }

    @Test func doesNotRequestFocusWhenKeyboardCaptureIsDisabled() {
        #expect(
            RenderSurfaceKeyboardFocusPolicy.shouldRefocus(
                previousCapturesKeyboardInput: true,
                currentCapturesKeyboardInput: false
            ) == false
        )
        #expect(
            RenderSurfaceKeyboardFocusPolicy.shouldRefocus(
                previousCapturesKeyboardInput: false,
                currentCapturesKeyboardInput: false
            ) == false
        )
    }
}
