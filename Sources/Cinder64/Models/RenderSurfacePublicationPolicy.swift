enum RenderSurfaceChangeKind: Equatable, Sendable {
    case attach
    case resize
    case reattach
}

enum RenderSurfacePublicationDecision: Equatable, Sendable {
    case clear
    case noChange
    case `defer`(RenderSurfaceDescriptor)
    case publish(RenderSurfaceDescriptor, kind: RenderSurfaceChangeKind)
}

enum RenderSurfacePublicationPolicy {
    static func decide(
        previousCommitted: RenderSurfaceDescriptor?,
        proposed: RenderSurfaceDescriptor?,
        isLiveResize: Bool
    ) -> RenderSurfacePublicationDecision {
        guard let proposed, proposed.isValid else {
            return previousCommitted == nil ? .noChange : .clear
        }

        guard let previousCommitted else {
            return .publish(proposed, kind: .attach)
        }

        if proposed.revision == previousCommitted.revision ||
            proposed.matchesCommittedGeometry(of: previousCommitted) {
            return .noChange
        }

        if isLiveResize && proposed.matchesSurfaceIdentity(of: previousCommitted) {
            return .defer(proposed)
        }

        if proposed.matchesSurfaceIdentity(of: previousCommitted) {
            return .publish(proposed, kind: .resize)
        }

        return .publish(proposed, kind: .reattach)
    }
}
