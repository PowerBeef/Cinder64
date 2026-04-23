import AppKit
import Foundation

struct EmbeddedKeyboardEvent: Equatable, Sendable {
    let scancode: Int32
    let isPressed: Bool
}

enum EmbeddedKeyboardScancodeMap {
    static func scancode(forMacKeyCode keyCode: UInt16) -> Int32? {
        switch keyCode {
        case 0: 4      // A
        case 1: 22     // S
        case 2: 7      // D
        case 6: 29     // Z
        case 7: 27     // X
        case 8: 6      // C
        case 13: 26    // W
        case 34: 12    // I
        case 37: 15    // L
        case 38: 13    // J
        case 40: 14    // K
        case 43: 54    // Comma
        case 36: 40    // Return
        case 56: 225   // Left Shift
        case 59: 224   // Left Control
        case 60: 229   // Right Shift
        case 62: 228   // Right Control
        case 123: 80   // Left Arrow
        case 124: 79   // Right Arrow
        case 125: 81   // Down Arrow
        case 126: 82   // Up Arrow
        default:
            nil
        }
    }

    /// Translate a Cocoa key event (keyDown / keyUp / flagsChanged)
    /// into an `EmbeddedKeyboardEvent` suitable for forwarding into
    /// `EmulationSession.handleKeyboardInput(_:)`. Returns `nil` when
    /// the event's key isn't part of the gameplay scancode map, or
    /// when it's a key-repeat (macOS emits held-key repeats while the
    /// N64 controller input state is already "held" from the first
    /// press, so repeats would double-enqueue).
    static func keyboardEvent(from event: NSEvent) -> EmbeddedKeyboardEvent? {
        switch event.type {
        case .flagsChanged:
            guard let scancode = scancode(forMacKeyCode: event.keyCode) else {
                return nil
            }

            let isPressed = switch event.keyCode {
            case 56, 60:
                event.modifierFlags.contains(.shift)
            case 59, 62:
                event.modifierFlags.contains(.control)
            default:
                false
            }

            return EmbeddedKeyboardEvent(scancode: scancode, isPressed: isPressed)
        case .keyDown:
            guard event.isARepeat == false else {
                return nil
            }
            fallthrough
        case .keyUp:
            guard let scancode = scancode(forMacKeyCode: event.keyCode) else {
                return nil
            }

            return EmbeddedKeyboardEvent(scancode: scancode, isPressed: event.type == .keyDown)
        default:
            return nil
        }
    }
}
