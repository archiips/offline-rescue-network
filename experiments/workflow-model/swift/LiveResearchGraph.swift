import Foundation

/// Maps original foreground readings into the bounded engine; contact supplies no floor constraint.
public enum LiveResearchGraph {
    private static func fresh(_ reading: ResearchFloorReading, at now: Double) -> Bool {
        now.isFinite && reading.sampledAt.isFinite && reading.sampledAt >= 0 && now >= reading.sampledAt &&
        now - reading.sampledAt <= 10 && reading.source != .unavailable &&
        reading.level.map { (-20...200).contains($0) } == true
    }
    public static func sharingReading(local: [ResearchFloorReading], now: Double) -> ResearchFloorReading? {
        let readings = local.filter { fresh($0, at: now) }
        guard let first = readings.first, readings.allSatisfy({ $0.level == first.level }) else { return nil }
        return first
    }
    public static func evaluate(local: [ResearchFloorReading], peer: ResearchPeerObservation?, now: Double) -> GraphFloorResult {
        var observations = local.filter { fresh($0, at: now) }.map {
            GraphFloorObservation(node: 1, origin: 1, observation: identifier($0.id), source: .sensor,
                                  minimumLevel: $0.level!, maximumLevel: $0.level!, elapsed: $0.sampledAt)
        }
        var edges: [GraphFloorEdge] = []
        if let peer, peer.isFresh(at: now), peer.receivedAt.isFinite, peer.age(at: now).isFinite,
           peer.age(at: now) >= 0, peer.receivedAt >= 0 {
            edges.append(.init(from: 1, to: 2, kind: .contact, elapsed: peer.receivedAt))
            if let level = peer.level, (-20...200).contains(level), peer.source != .unavailable {
                observations.append(.init(node: 2, origin: 2, observation: identifier(peer.id), source: .sensor,
                                          minimumLevel: level, maximumLevel: level, elapsed: max(0, now - peer.age(at: now))))
            }
        }
        return FloorGraph.evaluate(nodes: [1, 2], edges: edges, observations: observations, target: 1, now: now)
    }
    private static func identifier(_ id: UUID) -> UInt64 {
        var bytes = id.uuid
        let value = withUnsafeBytes(of: &bytes) { $0.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
        return value == 0 ? 1 : value
    }
}
