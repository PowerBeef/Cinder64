enum RenderSurfaceKeyboardFocusPolicy {
    static func shouldRefocus(
        previousCapturesKeyboardInput: Bool,
        currentCapturesKeyboardInput: Bool
    ) -> Bool {
        currentCapturesKeyboardInput && previousCapturesKeyboardInput == false
    }
}
