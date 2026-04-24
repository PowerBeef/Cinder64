import Foundation
import Testing
@testable import Cinder64

@Suite
struct SaveStateMetadataStoreTests {
    @Test func recordsProtectedCloseSavesSeparatelyFromManualSlots() throws {
        let temporaryDirectory = try TemporaryDirectoryFixture()
        let store = SaveStateMetadataStore(storageURL: temporaryDirectory.url("savestates.json"))
        let identity = ROMIdentity(
            id: "rom-super-mario-64",
            fileURL: temporaryDirectory.url("Super Mario 64.z64"),
            displayName: "Super Mario 64",
            sha256: "abc123"
        )

        try store.recordSaveState(
            for: identity,
            slot: 2,
            rendererName: "gopher64"
        )
        try store.recordSaveState(
            for: identity,
            slot: SaveStateMetadataStore.protectedCloseSlot,
            rendererName: "gopher64",
            kind: .protectedClose
        )

        let metadata = try store.loadMetadata()

        #expect(metadata[identity.id]?[2]?.kind == .manual)
        #expect(metadata[identity.id]?[SaveStateMetadataStore.protectedCloseSlot]?.kind == .protectedClose)
        #expect(try store.protectedCloseSave(for: identity)?.slot == SaveStateMetadataStore.protectedCloseSlot)
    }
}
