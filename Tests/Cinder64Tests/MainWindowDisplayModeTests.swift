import AppKit
import Testing

@testable import Cinder64

struct MainWindowDisplayModeTests {
    @Test func windowedModesProduceFixedContentSizes() {
        #expect(MainWindowPresentationPolicy.contentSize(for: .windowed1x) == NSSize(width: 900, height: 580))
        #expect(MainWindowPresentationPolicy.contentSize(for: .windowed2x) == NSSize(width: 1080, height: 680))
        #expect(MainWindowPresentationPolicy.contentSize(for: .windowed3x) == NSSize(width: 1260, height: 800))
        #expect(MainWindowPresentationPolicy.contentSize(for: .windowed4x) == NSSize(width: 1440, height: 920))
    }

    @Test func fullscreenModeDoesNotUseAWindowedContentSize() {
        #expect(MainWindowPresentationPolicy.contentSize(for: .fullscreen) == nil)
    }

    @Test func displayModeMapsToAndFromCoreUserSettings() {
        var settings = CoreUserSettings.default
        #expect(settings.windowScale == 1)
        #expect(MainWindowDisplayMode(settings: settings) == .windowed1x)

        MainWindowDisplayMode.windowed3x.apply(to: &settings)
        #expect(settings.startFullscreen == false)
        #expect(settings.windowScale == 3)
        #expect(MainWindowDisplayMode(settings: settings) == .windowed3x)

        MainWindowDisplayMode.fullscreen.apply(to: &settings)
        #expect(settings.startFullscreen)
        #expect(settings.windowScale == 3)
        #expect(MainWindowDisplayMode(settings: settings) == .fullscreen)
    }
}
