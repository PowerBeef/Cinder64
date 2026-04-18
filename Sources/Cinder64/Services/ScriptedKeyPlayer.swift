import Foundation

struct ScriptedKeyStep: Equatable, Sendable {
    let offsetMilliseconds: Int
    let scancode: Int32
    let isPressed: Bool
}

enum ScriptedKeyError: LocalizedError, Equatable {
    case malformedStep(String)
    case invalidField(String, String)
    case unknownState(String)
    case negativeOffset(Int)
    case decreasingOffset(Int, Int)

    var errorDescription: String? {
        switch self {
        case let .malformedStep(step):
            "Scripted key step must be \"ms:scancode:down|up\", got \"\(step)\"."
        case let .invalidField(field, value):
            "Scripted key \(field) must be an integer, got \"\(value)\"."
        case let .unknownState(state):
            "Scripted key state must be \"down\" or \"up\", got \"\(state)\"."
        case let .negativeOffset(offset):
            "Scripted key offsets must be non-negative, got \(offset)."
        case let .decreasingOffset(previous, next):
            "Scripted key offsets must be monotonically non-decreasing, got \(next) after \(previous)."
        }
    }
}

enum ScriptedKeySequence {
    static func parse(_ raw: String) throws -> [ScriptedKeyStep] {
        var steps: [ScriptedKeyStep] = []
        let chunks = raw
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }

        for chunk in chunks {
            let fields = chunk.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 3 else {
                throw ScriptedKeyError.malformedStep(chunk)
            }

            guard let offset = Int(fields[0]) else {
                throw ScriptedKeyError.invalidField("offset", fields[0])
            }
            if offset < 0 {
                throw ScriptedKeyError.negativeOffset(offset)
            }

            guard let scancode = Int32(fields[1]) else {
                throw ScriptedKeyError.invalidField("scancode", fields[1])
            }

            let isPressed: Bool
            switch fields[2].lowercased() {
            case "down": isPressed = true
            case "up": isPressed = false
            default: throw ScriptedKeyError.unknownState(fields[2])
            }

            if let last = steps.last, offset < last.offsetMilliseconds {
                throw ScriptedKeyError.decreasingOffset(last.offsetMilliseconds, offset)
            }

            steps.append(ScriptedKeyStep(
                offsetMilliseconds: offset,
                scancode: scancode,
                isPressed: isPressed
            ))
        }

        return steps
    }
}

@MainActor
protocol ScriptedKeyReceiver: AnyObject {
    func handleKeyboardInput(_ event: EmbeddedKeyboardEvent)
}

extension EmulationSession: ScriptedKeyReceiver {}

@MainActor
final class ScriptedKeyPlayer {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias Logger = @MainActor (String) -> Void

    private let steps: [ScriptedKeyStep]
    private let sleep: Sleep
    private let log: Logger

    init(
        steps: [ScriptedKeyStep],
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        log: @escaping Logger = { _ in }
    ) {
        self.steps = steps
        self.sleep = sleep
        self.log = log
    }

    var stepCount: Int { steps.count }

    func play(on receiver: ScriptedKeyReceiver) async {
        var elapsedMilliseconds = 0

        for (index, step) in steps.enumerated() {
            let delta = step.offsetMilliseconds - elapsedMilliseconds
            if delta > 0 {
                do {
                    try await sleep(.milliseconds(delta))
                } catch {
                    log("scripted-key playback interrupted before step \(index + 1)")
                    return
                }
            }
            elapsedMilliseconds = step.offsetMilliseconds

            receiver.handleKeyboardInput(
                EmbeddedKeyboardEvent(scancode: step.scancode, isPressed: step.isPressed)
            )
            log("scripted-key step \(index + 1) executed scancode=\(step.scancode) pressed=\(step.isPressed) at +\(step.offsetMilliseconds)ms")
        }
    }
}
