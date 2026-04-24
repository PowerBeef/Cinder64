import Foundation
import Testing
@testable import Cinder64

@Suite
struct RuntimeMetricsArtifactStoreTests {
    @Test func writesMetricsArtifactsUnderTheAppSupportRoot() throws {
        let persistence = try PersistenceFixture()
        let store = RuntimeMetricsArtifactStore(logStore: persistence.persistence.logStore)

        store.update { artifact in
            artifact.startupPhases = ["open-requested", "rom-opened"]
            artifact.pumpTickCount = 42
            artifact.viCount = 60
            artifact.renderFrameCount = 39
            artifact.presentCount = 39
            artifact.currentFPS = 39
            artifact.lastStructuredError = RuntimeMetricsArtifactError(message: "test-error")
        }

        let data = try Data(contentsOf: persistence.metricsURL)
        let artifact = try JSONDecoder.iso8601.decode(RuntimeMetricsArtifact.self, from: data)

        #expect(artifact.startupPhases == ["open-requested", "rom-opened"])
        #expect(artifact.pumpTickCount == 42)
        #expect(artifact.viCount == 60)
        #expect(artifact.renderFrameCount == 39)
        #expect(artifact.presentCount == 39)
        #expect(artifact.currentFPS == 39)
        #expect(artifact.lastStructuredError == RuntimeMetricsArtifactError(message: "test-error"))
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
