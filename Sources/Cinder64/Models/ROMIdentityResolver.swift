import Foundation

struct ROMIdentityResolver: Sendable {
    private let resolve: @Sendable (URL) async throws -> ROMIdentity

    init(resolve: @escaping @Sendable (URL) async throws -> ROMIdentity) {
        self.resolve = resolve
    }

    func identity(for url: URL) async throws -> ROMIdentity {
        try await resolve(url)
    }

    static let live = ROMIdentityResolver { url in
        try await Task.detached(priority: .userInitiated) {
            try ROMIdentity.make(for: url)
        }.value
    }

    static let immediate = ROMIdentityResolver { url in
        try ROMIdentity.make(for: url)
    }
}
