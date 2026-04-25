import Foundation
import Testing
@testable import Cinder64

@Suite
struct EmulationRuntimeActorTests {
    @Test func pumpCommandsDoNotOverlapWhileOneIsInFlight() async throws {
        let executor = RuntimeCommandRecorder()
        let runtime = EmulationRuntimeActor(execute: executor.execute)

        let first = Task { try await runtime.send(.pump) }
        await waitUntil("first pump") {
            await executor.commandsSnapshot() == [.pump]
        }

        let second = try await runtime.send(.pump)
        #expect(second == .skipped)
        #expect(await executor.commandsSnapshot() == [.pump])

        await executor.release()
        _ = try await first.value

        await executor.setShouldSuspend(false)
        let third = try await runtime.send(.pump)
        #expect(third == .none)
        #expect(await executor.commandsSnapshot() == [.pump, .pump])
    }

    @Test func commandsRunInSubmissionOrder() async throws {
        let executor = RuntimeCommandRecorder()
        let runtime = EmulationRuntimeActor(execute: executor.execute)

        let pause = Task { try await runtime.send(.pause) }
        await waitUntil("pause command") {
            await executor.commandsSnapshot() == [.pause]
        }

        let resume = Task { try await runtime.send(.resume) }
        await waitUntil("resume command") {
            await executor.commandsSnapshot() == [.pause, .resume]
        }

        await executor.release()
        _ = try await pause.value
        await executor.release()
        _ = try await resume.value

        #expect(await executor.commandsSnapshot() == [.pause, .resume])
    }
}

private actor RuntimeCommandRecorder {
    private var commands: [RuntimeCommand] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspend = true

    func execute(_ command: RuntimeCommand) async throws -> RuntimeCommandResult {
        commands.append(command)
        if shouldSuspend {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }
        return .none
    }

    func setShouldSuspend(_ shouldSuspend: Bool) {
        self.shouldSuspend = shouldSuspend
    }

    func commandsSnapshot() -> [RuntimeCommand] {
        commands
    }

    func release() {
        guard continuations.isEmpty == false else { return }
        continuations.removeFirst().resume()
    }
}

private func waitUntil(
    _ description: String,
    timeoutIterations: Int = 1_000,
    condition: () async -> Bool
) async {
    for _ in 0..<timeoutIterations {
        if await condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for \(description)")
}
