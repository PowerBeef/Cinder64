import Foundation
@testable import Cinder64

func makeIdentity(name: String) -> ROMIdentity {
    ROMIdentity(
        id: "rom-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
        fileURL: URL(fileURLWithPath: "/tmp/\(name).z64"),
        displayName: name,
        sha256: "sha-\(name)"
    )
}
