import Foundation
import Testing
@testable import Cinder64

@Suite
struct ROMIdentityTests {
    @Test func idIsDerivedFromTheHashPrefixNotTheDisplayName() throws {
        let directory = try TemporaryDirectoryFixture()
        let romURL = try ROMFixture.writeROM(named: "Same Name.z64", in: directory.directory, bytes: Data("first-rom".utf8))

        let identity = try ROMIdentity.make(for: romURL)

        #expect(identity.id == "rom-\(identity.sha256.prefix(16))")
        #expect(identity.displayName == "Same Name")
    }

    @Test func filesWithTheSameDisplayNameAndDifferentBytesDoNotCollide() throws {
        let firstDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-rom-a")
        let secondDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-rom-b")
        let firstURL = try ROMFixture.writeROM(named: "Same Name.z64", in: firstDirectory.directory, bytes: Data("first-rom".utf8))
        let secondURL = try ROMFixture.writeROM(named: "Same Name.z64", in: secondDirectory.directory, bytes: Data("second-rom".utf8))

        let firstIdentity = try ROMIdentity.make(for: firstURL)
        let secondIdentity = try ROMIdentity.make(for: secondURL)

        #expect(firstIdentity.displayName == secondIdentity.displayName)
        #expect(firstIdentity.sha256 != secondIdentity.sha256)
        #expect(firstIdentity.id != secondIdentity.id)
    }

    @Test func sameBytesProduceStableIDs() throws {
        let firstDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-rom-a")
        let secondDirectory = try TemporaryDirectoryFixture(prefix: "cinder64-rom-b")
        let bytes = Data("stable-rom".utf8)
        let firstURL = try ROMFixture.writeROM(named: "Stable One.z64", in: firstDirectory.directory, bytes: bytes)
        let secondURL = try ROMFixture.writeROM(named: "Stable Two.z64", in: secondDirectory.directory, bytes: bytes)

        let firstIdentity = try ROMIdentity.make(for: firstURL)
        let secondIdentity = try ROMIdentity.make(for: secondURL)

        #expect(firstIdentity.id == secondIdentity.id)
    }
}
