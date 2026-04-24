import Foundation
import Testing
@testable import Cinder64

enum ROMFixture {
    static func writeROM(
        named name: String,
        in directory: URL,
        bytes: Data = Data("rom-data".utf8)
    ) throws -> URL {
        let url = directory.appending(path: name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
        return url
    }

    static func writeValidHeaderROM(named name: String, in directory: URL) throws -> URL {
        try writeROM(named: name, in: directory, bytes: Data(validHeaderBytes()))
    }

    static func writeInvalidROM(named name: String, in directory: URL) throws -> URL {
        try writeROM(named: name, in: directory, bytes: Data("definitely-not-a-real-rom".utf8))
    }

    static func validHeaderBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4096)
        bytes[0] = 0x80
        bytes[1] = 0x37
        bytes[2] = 0x12
        bytes[3] = 0x40
        return bytes
    }

    static func zipItem(at sourceURL: URL, into archiveURL: URL, from workingDirectory: URL) throws {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", archiveURL.lastPathComponent, sourceURL.lastPathComponent]

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }
}
