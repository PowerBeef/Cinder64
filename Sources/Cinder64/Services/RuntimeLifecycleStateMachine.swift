import Foundation

enum RuntimeLifecycleState: String, Sendable {
    case stopped
    case booting
    case readyPaused
    case running
    case paused
    case stopping
    case failed
    case disposed
}

struct RuntimeLifecycleStateMachine: Sendable {
    enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidTransition(from: RuntimeLifecycleState, to: RuntimeLifecycleState)

        var errorDescription: String? {
            switch self {
            case let .invalidTransition(from, to):
                "Invalid runtime lifecycle transition from \(from.rawValue) to \(to.rawValue)."
            }
        }
    }

    private(set) var state: RuntimeLifecycleState = .stopped

    mutating func transition(to nextState: RuntimeLifecycleState) throws {
        guard Self.allowedTransitions[state, default: []].contains(nextState) else {
            throw Error.invalidTransition(from: state, to: nextState)
        }

        state = nextState
    }

    mutating func force(_ nextState: RuntimeLifecycleState) {
        state = nextState
    }

    private static let allowedTransitions: [RuntimeLifecycleState: Set<RuntimeLifecycleState>] = [
        .stopped: [.booting, .disposed],
        .booting: [.readyPaused, .stopping, .failed, .stopped],
        .readyPaused: [.running, .stopping, .failed, .stopped],
        .running: [.paused, .stopping, .failed, .stopped],
        .paused: [.running, .stopping, .failed, .stopped],
        .stopping: [.stopped, .failed, .disposed],
        .failed: [.stopping, .stopped, .disposed, .booting],
        .disposed: [.stopped],
    ]
}
