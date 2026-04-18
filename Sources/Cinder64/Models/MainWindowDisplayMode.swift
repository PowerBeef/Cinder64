import AppKit
import Foundation

enum MainWindowDisplayMode: String, CaseIterable, Codable, Equatable, Sendable {
    case windowed1x
    case windowed2x
    case windowed3x
    case windowed4x
    case fullscreen

    init(settings: CoreUserSettings) {
        if settings.startFullscreen {
            self = .fullscreen
            return
        }

        switch settings.windowScale {
        case 1:
            self = .windowed1x
        case 2:
            self = .windowed2x
        case 3:
            self = .windowed3x
        case 4:
            self = .windowed4x
        default:
            self = .windowed2x
        }
    }

    var title: String {
        switch self {
        case .windowed1x:
            "1x Windowed"
        case .windowed2x:
            "2x Windowed"
        case .windowed3x:
            "3x Windowed"
        case .windowed4x:
            "4x Windowed"
        case .fullscreen:
            "Fullscreen"
        }
    }

    var isFullscreen: Bool {
        self == .fullscreen
    }

    var windowScale: Int? {
        switch self {
        case .windowed1x:
            1
        case .windowed2x:
            2
        case .windowed3x:
            3
        case .windowed4x:
            4
        case .fullscreen:
            nil
        }
    }

    func apply(to settings: inout CoreUserSettings) {
        settings.startFullscreen = isFullscreen
        if let windowScale {
            settings.windowScale = windowScale
        }
    }
}

enum MainWindowPresentationPolicy {
    static func contentSize(for mode: MainWindowDisplayMode) -> NSSize? {
        switch mode {
        case .windowed1x:
            NSSize(width: 900, height: 580)
        case .windowed2x:
            NSSize(width: 1080, height: 680)
        case .windowed3x:
            NSSize(width: 1260, height: 800)
        case .windowed4x:
            NSSize(width: 1440, height: 920)
        case .fullscreen:
            nil
        }
    }

    static func fittedContentSize(_ size: NSSize, visibleFrame: CGRect?) -> NSSize {
        guard let visibleFrame else {
            return size
        }

        return NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
    }
}
