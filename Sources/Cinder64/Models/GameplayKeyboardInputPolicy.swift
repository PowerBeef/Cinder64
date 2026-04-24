import AppKit
import Foundation

struct GameplayKeyboardInputContext: Equatable, Sendable {
    let emulationState: EmulationState
    let hasVisiblePrompt: Bool
    let isAppActive: Bool
    let isEventInTrackedWindow: Bool
}

enum GameplayKeyboardInputDecision: Equatable, Sendable {
    case forward(EmbeddedKeyboardEvent)
    case passThrough
}

enum GameplayKeyboardInputPolicy {
    static func decision(
        for event: NSEvent,
        context: GameplayKeyboardInputContext
    ) -> GameplayKeyboardInputDecision {
        guard context.emulationState == .running || context.emulationState == .paused else {
            return .passThrough
        }

        guard context.hasVisiblePrompt == false,
              context.isAppActive,
              context.isEventInTrackedWindow else {
            return .passThrough
        }

        let blockingModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockingModifiers).isEmpty else {
            return .passThrough
        }

        guard let keyboardEvent = EmbeddedKeyboardScancodeMap.keyboardEvent(from: event) else {
            return .passThrough
        }

        return .forward(keyboardEvent)
    }
}
