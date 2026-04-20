import Testing
@testable import Cinder64

struct RuntimeLifecycleStateMachineTests {
    @Test func lifecycleAllowsTheExpectedHostedRuntimePath() throws {
        var machine = RuntimeLifecycleStateMachine()

        try machine.transition(to: .booting)
        try machine.transition(to: .readyPaused)
        try machine.transition(to: .running)
        try machine.transition(to: .paused)
        try machine.transition(to: .running)
        try machine.transition(to: .stopping)
        try machine.transition(to: .stopped)
        try machine.transition(to: .disposed)

        #expect(machine.state == .disposed)
    }

    @Test func lifecycleRejectsInvalidTransitions() {
        var machine = RuntimeLifecycleStateMachine()

        #expect(throws: RuntimeLifecycleStateMachine.Error.self) {
            try machine.transition(to: .running)
        }

        #expect(machine.state == .stopped)
    }
}
