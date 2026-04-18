import Foundation

@MainActor
final class LaunchRequestBroker {
    typealias LaunchHandler = @MainActor (URL) async -> Void

    static let shared = LaunchRequestBroker(arguments: CommandLine.arguments)

    private var pendingURL: URL?
    private var launchHandler: LaunchHandler?
    private var isDeliveringLaunch = false
    private var inFlightURL: URL?
    let scriptedKeySteps: [ScriptedKeyStep]
    let scriptedKeyParseError: String?

    init(arguments: [String]) {
        pendingURL = Self.extractLaunchURLs(from: arguments).last
        let scripted = Self.parseScriptedKeys(from: arguments)
        scriptedKeySteps = scripted.steps
        scriptedKeyParseError = scripted.error
    }

    func installHandler(_ handler: @escaping LaunchHandler) async {
        launchHandler = handler
        await deliverPendingLaunchIfNeeded()
    }

    func enqueue(_ url: URL) {
        let standardizedURL = url.standardizedFileURL

        guard standardizedURL != inFlightURL else {
            return
        }

        pendingURL = standardizedURL
        Task { await deliverPendingLaunchIfNeeded() }
    }

    private func deliverPendingLaunchIfNeeded() async {
        guard isDeliveringLaunch == false else {
            return
        }

        guard let launchHandler, pendingURL != nil else {
            return
        }

        isDeliveringLaunch = true
        defer {
            isDeliveringLaunch = false
            inFlightURL = nil
        }

        while let nextURL = pendingURL {
            pendingURL = nil
            inFlightURL = nextURL
            await launchHandler(nextURL)
        }
    }

    private static func extractLaunchURLs(from arguments: [String]) -> [URL] {
        var launchURLs: [URL] = []
        var iterator = arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--app-support-root", "--scripted-keys":
                _ = iterator.next()
            default:
                guard argument.hasPrefix("-") == false else {
                    continue
                }

                launchURLs.append(URL(fileURLWithPath: argument).standardizedFileURL)
            }
        }

        return launchURLs
    }

    private static func parseScriptedKeys(from arguments: [String]) -> (steps: [ScriptedKeyStep], error: String?) {
        var iterator = arguments.dropFirst().makeIterator()
        var rawValue: String?

        while let argument = iterator.next() {
            if argument == "--scripted-keys" {
                rawValue = iterator.next()
            } else if argument == "--app-support-root" {
                _ = iterator.next()
            }
        }

        guard let rawValue, rawValue.isEmpty == false else {
            return ([], nil)
        }

        do {
            return (try ScriptedKeySequence.parse(rawValue), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }
}
