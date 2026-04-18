import AppKit
import Testing
@testable import Cinder64

struct EmbeddedKeyboardScancodeMapTests {
    @Test func mapsDefaultNintendo64KeyboardBindingsFromMacKeyCodes() {
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 36) == 40)   // Return -> Start
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 13) == 26)   // W -> stick up
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 0) == 4)     // A -> stick left
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 1) == 22)    // S -> stick down
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 2) == 7)     // D -> stick right
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 123) == 80)  // Left arrow
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 124) == 79)  // Right arrow
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 125) == 81)  // Down arrow
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 126) == 82)  // Up arrow
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 59) == 224)  // Left control
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 56) == 225)  // Left shift
    }

    @Test func ignoresUnsupportedMacKeyCodes() {
        #expect(EmbeddedKeyboardScancodeMap.scancode(forMacKeyCode: 999) == nil)
    }
}
