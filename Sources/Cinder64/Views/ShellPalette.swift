import SwiftUI

enum ShellPalette {
    static let accent = Color(red: 0.83, green: 0.38, blue: 0.20)
    static let accentSoft = accent.opacity(0.15)
    static let accentGlow = accent.opacity(0.08)
    static let line = Color.white.opacity(0.08)
    static let strongLine = Color.white.opacity(0.12)
    static let stageShadow = Color.black.opacity(0.10)
    static let offBlack = Color(red: 0.04, green: 0.04, blue: 0.05)
}
