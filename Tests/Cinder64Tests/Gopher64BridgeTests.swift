import Cinder64BridgeABI
import Testing
@testable import Cinder64

@Suite
struct Gopher64BridgeTests {
    @Test func missingRequiredFunctionPointerThrowsTypedError() throws {
        var api = Cinder64BridgeAPI()
        api.abi_version = UInt32(CINDER64_BRIDGE_ABI_VERSION)
        api.struct_size = UInt32(MemoryLayout<Cinder64BridgeAPI>.size)

        #expect(throws: Gopher64BridgeError.missingFunctionPointer(name: "create_session")) {
            try Gopher64Bridge.validateRequiredFunctionPointersForTesting(api)
        }
    }
}
