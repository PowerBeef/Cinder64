import Foundation

enum EmulationState: String, Codable, Equatable, Sendable {
    case stopped
    case booting
    case paused
    case running
    case failed
}

enum VideoMode: String, Codable, Equatable, Sendable {
    case none
    case windowed
    case fullscreen
}

struct WarningBanner: Codable, Equatable, Sendable {
    let title: String
    let message: String
}

struct SessionSnapshot: Codable, Equatable, Sendable {
    var emulationState: EmulationState
    var activeROM: ROMIdentity?
    var rendererName: String
    var fps: Double
    var videoMode: VideoMode
    var audioMuted: Bool
    var activeSaveSlot: Int
    var warningBanner: WarningBanner?

    static let idle = SessionSnapshot(
        emulationState: .stopped,
        activeROM: nil,
        rendererName: "gopher64 (idle)",
        fps: 0,
        videoMode: .none,
        audioMuted: false,
        activeSaveSlot: 0,
        warningBanner: nil
    )
}
