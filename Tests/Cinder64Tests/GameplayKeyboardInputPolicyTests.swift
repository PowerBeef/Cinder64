import AppKit
import Testing
@testable import Cinder64

@MainActor
@Suite
struct GameplayKeyboardInputPolicyTests {
    @Test func forwardsMappedGameplayKeysWhenTheRuntimeIsPlayable() throws {
        let decision = GameplayKeyboardInputPolicy.decision(
            for: keyEvent(type: .keyDown, keyCode: 36),
            context: GameplayKeyboardInputContext(
                emulationState: .running,
                hasVisiblePrompt: false,
                isAppActive: true,
                isEventInTrackedWindow: true
            )
        )

        #expect(decision == .forward(EmbeddedKeyboardEvent(scancode: 40, isPressed: true)))
    }

    @Test(arguments: [
        GameplayKeyboardInputContext(emulationState: .stopped, hasVisiblePrompt: false, isAppActive: true, isEventInTrackedWindow: true),
        GameplayKeyboardInputContext(emulationState: .running, hasVisiblePrompt: true, isAppActive: true, isEventInTrackedWindow: true),
        GameplayKeyboardInputContext(emulationState: .running, hasVisiblePrompt: false, isAppActive: false, isEventInTrackedWindow: true),
        GameplayKeyboardInputContext(emulationState: .running, hasVisiblePrompt: false, isAppActive: true, isEventInTrackedWindow: false),
    ])
    func passesThroughWhenContextIsNotGameplayEligible(_ context: GameplayKeyboardInputContext) throws {
        let decision = GameplayKeyboardInputPolicy.decision(
            for: keyEvent(type: .keyDown, keyCode: 36),
            context: context
        )

        #expect(decision == .passThrough)
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.command,
        NSEvent.ModifierFlags.control,
        NSEvent.ModifierFlags.option,
    ])
    func passesThroughShortcutModifiers(_ modifier: NSEvent.ModifierFlags) throws {
        let decision = GameplayKeyboardInputPolicy.decision(
            for: keyEvent(type: .keyDown, keyCode: 36, modifiers: modifier),
            context: .playable
        )

        #expect(decision == .passThrough)
    }

    @Test func passesThroughUnmappedKeysAndRepeats() throws {
        let unmappedDecision = GameplayKeyboardInputPolicy.decision(
            for: keyEvent(type: .keyDown, keyCode: 99),
            context: .playable
        )
        let repeatDecision = GameplayKeyboardInputPolicy.decision(
            for: keyEvent(type: .keyDown, keyCode: 36, isARepeat: true),
            context: .playable
        )

        #expect(unmappedDecision == .passThrough)
        #expect(repeatDecision == .passThrough)
    }

    private func keyEvent(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 1,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: keyCode
        )!
    }
}

private extension GameplayKeyboardInputContext {
    static let playable = GameplayKeyboardInputContext(
        emulationState: .running,
        hasVisiblePrompt: false,
        isAppActive: true,
        isEventInTrackedWindow: true
    )
}
