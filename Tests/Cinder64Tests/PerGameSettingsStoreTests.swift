import Foundation
import Testing
@testable import Cinder64

struct PerGameSettingsStoreTests {
    @Test func migratesLegacyMupenRendererSettingsToGopherDefaults() throws {
        let harness = try TemporaryDirectoryHarness()
        let identity = makeIdentity(name: "Wave Race 64")
        let storageURL = harness.directory.appending(path: "per-game-settings.json")
        let legacyJSON = """
        {
          "\(identity.id)" : {
            "muteAudio" : true,
            "rendererBackend" : "moltenVK",
            "speedPercent" : 85,
            "startFullscreen" : true
          }
        }
        """
        try Data(legacyJSON.utf8).write(to: storageURL)

        let store = PerGameSettingsStore(storageURL: storageURL)
        let settings = try #require(try store.loadSettings(for: identity))

        #expect(settings.startFullscreen)
        #expect(settings.windowScale == 1)
        #expect(settings.muteAudio)
        #expect(settings.speedPercent == 85)
        #expect(settings.upscaleMultiplier == 2)
        #expect(settings.integerScaling == false)
        #expect(settings.crtFilterEnabled == false)
    }
}
