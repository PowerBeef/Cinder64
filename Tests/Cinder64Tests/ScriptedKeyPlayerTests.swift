import Foundation
import Testing
@testable import Cinder64

@MainActor
struct ScriptedKeyPlayerTests {
    @Test func parsesWellFormedSequence() throws {
        let steps = try ScriptedKeySequence.parse("0:40:down;60:40:up ; 2500:44:down;2560:44:up")

        #expect(steps == [
            ScriptedKeyStep(offsetMilliseconds: 0, scancode: 40, isPressed: true),
            ScriptedKeyStep(offsetMilliseconds: 60, scancode: 40, isPressed: false),
            ScriptedKeyStep(offsetMilliseconds: 2500, scancode: 44, isPressed: true),
            ScriptedKeyStep(offsetMilliseconds: 2560, scancode: 44, isPressed: false),
        ])
    }

    @Test func skipsEmptyChunks() throws {
        let steps = try ScriptedKeySequence.parse(";;10:40:down;;")

        #expect(steps == [ScriptedKeyStep(offsetMilliseconds: 10, scancode: 40, isPressed: true)])
    }

    @Test func rejectsMalformedStep() {
        #expect(throws: ScriptedKeyError.malformedStep("10:40")) {
            try ScriptedKeySequence.parse("10:40")
        }
    }

    @Test func rejectsUnknownState() {
        #expect(throws: ScriptedKeyError.unknownState("hold")) {
            try ScriptedKeySequence.parse("10:40:hold")
        }
    }

    @Test func rejectsDecreasingOffsets() {
        #expect(throws: ScriptedKeyError.decreasingOffset(100, 50)) {
            try ScriptedKeySequence.parse("100:40:down;50:40:up")
        }
    }

    @Test func rejectsNegativeOffset() {
        #expect(throws: ScriptedKeyError.negativeOffset(-1)) {
            try ScriptedKeySequence.parse("-1:40:down")
        }
    }

    @Test func playerDeliversStepsInOrder() async {
        let receiver = RecordingReceiver()
        let sleepCalls = SleepRecorder()
        let steps = [
            ScriptedKeyStep(offsetMilliseconds: 100, scancode: 40, isPressed: true),
            ScriptedKeyStep(offsetMilliseconds: 160, scancode: 40, isPressed: false),
            ScriptedKeyStep(offsetMilliseconds: 500, scancode: 44, isPressed: true),
        ]
        let logMessages = LogRecorder()
        let player = ScriptedKeyPlayer(
            steps: steps,
            sleep: { duration in await sleepCalls.record(duration) },
            log: { message in logMessages.append(message) }
        )

        await player.play(on: receiver)

        #expect(receiver.events == [
            EmbeddedKeyboardEvent(scancode: 40, isPressed: true),
            EmbeddedKeyboardEvent(scancode: 40, isPressed: false),
            EmbeddedKeyboardEvent(scancode: 44, isPressed: true),
        ])
        #expect(await sleepCalls.durations == [
            .milliseconds(100),
            .milliseconds(60),
            .milliseconds(340),
        ])
        #expect(logMessages.messages.count == 3)
        #expect(logMessages.messages[0].contains("step 1"))
        #expect(logMessages.messages[2].contains("step 3"))
    }

    @Test func playerStopsWhenSleepIsCancelled() async {
        let receiver = RecordingReceiver()
        let steps = [
            ScriptedKeyStep(offsetMilliseconds: 0, scancode: 40, isPressed: true),
            ScriptedKeyStep(offsetMilliseconds: 100, scancode: 40, isPressed: false),
        ]
        let logMessages = LogRecorder()
        let player = ScriptedKeyPlayer(
            steps: steps,
            sleep: { _ in throw CancellationError() },
            log: { message in logMessages.append(message) }
        )

        await player.play(on: receiver)

        #expect(receiver.events == [EmbeddedKeyboardEvent(scancode: 40, isPressed: true)])
        #expect(logMessages.messages.contains { $0.contains("interrupted") })
    }
}

@MainActor
private final class RecordingReceiver: ScriptedKeyReceiver {
    var events: [EmbeddedKeyboardEvent] = []

    func handleKeyboardInput(_ event: EmbeddedKeyboardEvent) {
        events.append(event)
    }
}

private actor SleepRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}

@MainActor
private final class LogRecorder {
    var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
    }
}
