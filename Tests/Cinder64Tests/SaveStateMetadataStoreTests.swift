import Foundation
import Testing
@testable import Cinder64

struct SaveStateMetadataStoreTests {
    @Test func recordsProtectedCloseSavesSeparatelyFromManualSlots() throws {
        let harness = try TemporaryDirectoryHarness()
        let store = SaveStateMetadataStore(storageURL: harness.directory.appending(path: "savestates.json"))
        let identity = ROMIdentity(
            id: "rom-super-mario-64",
            fileURL: harness.directory.appending(path: "Super Mario 64.z64"),
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
