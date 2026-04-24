import CryptoKit
import Foundation

struct ROMIdentity: Codable, Equatable, Hashable, Sendable {
    let id: String
    let fileURL: URL
    let displayName: String
    let sha256: String

    static func make(for url: URL) throws -> ROMIdentity {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        let sha256 = digest.map { String(format: "%02x", $0) }.joined()
        let displayName = url.deletingPathExtension().lastPathComponent
        return ROMIdentity(
            id: "rom-\(sha256.prefix(16))",
            fileURL: url.standardizedFileURL,
            displayName: displayName,
            sha256: sha256
        )
    }
}
