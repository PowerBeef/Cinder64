import Foundation
import Testing
@testable import Cinder64

@MainActor
struct LaunchRequestBrokerTests {
    @Test func plainStartupWithoutLaunchArgumentsDoesNotDeliverAROM() async throws {
        let broker = LaunchRequestBroker(arguments: ["Cinder64"])
        var launchedURLs: [URL] = []

        await broker.installHandler { launchedURLs.append($0) }

        #expect(launchedURLs.isEmpty)
    }

    @Test func startupArgumentsAreQueuedUntilAHandlerIsInstalled() async throws {
        let romURL = URL(fileURLWithPath: "/tmp/Super Mario 64.z64").standardizedFileURL
        let broker = LaunchRequestBroker(arguments: ["Cinder64", romURL.path])
        var launchedURLs: [URL] = []

        await broker.installHandler { launchedURLs.append($0) }

        #expect(launchedURLs == [romURL])
    }

    @Test func overlappingLaunchRequestsCollapseToTheNewestPendingROM() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/Wave Race 64.z64").standardizedFileURL
        let secondURL = URL(fileURLWithPath: "/tmp/Star Fox 64.z64").standardizedFileURL
        let thirdURL = URL(fileURLWithPath: "/tmp/F-Zero X.z64").standardizedFileURL
        let broker = LaunchRequestBroker(arguments: ["Cinder64"])

        var launchedURLs: [URL] = []
        var releaseFirstLaunch: CheckedContinuation<Void, Never>?

        await broker.installHandler { url in
            launchedURLs.append(url)

            if url == firstURL {
                await withCheckedContinuation { continuation in
                    releaseFirstLaunch = continuation
                }
            }
        }

        broker.enqueue(firstURL)

        while launchedURLs.isEmpty {
            await Task.yield()
        }

        broker.enqueue(secondURL)
        broker.enqueue(thirdURL)
        releaseFirstLaunch?.resume()

        while launchedURLs.count < 2 {
            await Task.yield()
        }

        #expect(launchedURLs == [firstURL, thirdURL])
    }

    @Test func appSupportOverrideArgumentsAreIgnoredWhenCollectingLaunchROMs() async throws {
        let romURL = URL(fileURLWithPath: "/tmp/Super Mario 64.z64").standardizedFileURL
        let broker = LaunchRequestBroker(arguments: [
            "Cinder64",
            "--app-support-root",
            "/tmp/cinder64-smoke-root",
            romURL.path,
        ])
        var launchedURLs: [URL] = []

        await broker.installHandler { launchedURLs.append($0) }

        #expect(launchedURLs == [romURL])
    }

    @Test func scriptedKeyStepsCanBeLoadedFromTheEnvironment() async throws {
        let broker = LaunchRequestBroker(
            arguments: ["Cinder64"],
            environment: [
                "CINDER64_SCRIPTED_KEYS": "100:40:down;200:40:up",
            ]
        )

        #expect(broker.scriptedKeyParseError == nil)
        #expect(broker.scriptedKeySteps == [
            ScriptedKeyStep(offsetMilliseconds: 100, scancode: 40, isPressed: true),
            ScriptedKeyStep(offsetMilliseconds: 200, scancode: 40, isPressed: false),
        ])
    }

    @Test func commandLineScriptedKeysOverrideTheEnvironment() async throws {
        let broker = LaunchRequestBroker(
            arguments: [
                "Cinder64",
                "--scripted-keys",
                "100:40:down",
            ],
            environment: [
                "CINDER64_SCRIPTED_KEYS": "200:41:down",
            ]
        )

        #expect(broker.scriptedKeyParseError == nil)
        #expect(broker.scriptedKeySteps == [
            ScriptedKeyStep(offsetMilliseconds: 100, scancode: 40, isPressed: true),
        ])
    }
}
