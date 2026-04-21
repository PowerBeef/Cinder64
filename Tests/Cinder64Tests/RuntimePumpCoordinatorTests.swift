import Testing
@testable import Cinder64

@MainActor
struct RuntimePumpCoordinatorTests {
    @Test func blockedTicksCoalesceIntoASingleDeferredPump() {
        var pumpCount = 0
        let coordinator = RuntimePumpCoordinator(useDisplayLink: false) {
            pumpCount += 1
        }

        coordinator.start()
        coordinator.setBlocked(true)
        coordinator.requestPumpTickForTesting()
        coordinator.requestPumpTickForTesting()

        #expect(pumpCount == 0)

        coordinator.setBlocked(false)

        #expect(pumpCount == 1)
    }

    @Test func stoppingTheCoordinatorPreventsFurtherPumpRequests() {
        var pumpCount = 0
        let coordinator = RuntimePumpCoordinator(useDisplayLink: false) {
            pumpCount += 1
        }

        coordinator.start()
        coordinator.requestPumpTickForTesting()
        coordinator.stop()
        coordinator.requestPumpTickForTesting()

        #expect(pumpCount == 1)
        #expect(coordinator.isUsingDisplayLinkForTesting == false)
    }
}
