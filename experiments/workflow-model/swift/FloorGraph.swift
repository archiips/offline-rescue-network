import RescueDemoBridge

public enum GraphFloorSource: Int32, Sendable { case sensor, surveyedWiFi, knownReference }
public enum GraphFloorEdgeKind: Int32, Sendable { case contact, relativeLevel }

/// Original local/replay reference. Copies retain origin+observation IDs; never feed derived graph
/// results back as independent observations. A future live adapter must authenticate and age evidence.
public struct GraphFloorObservation: Sendable {
    public let node, origin, observation: UInt64
    public let source: GraphFloorSource
    public let minimumLevel, maximumLevel: Int
    public let elapsed: Double
    public init(node: UInt64, origin: UInt64, observation: UInt64, source: GraphFloorSource,
                minimumLevel: Int, maximumLevel: Int, elapsed: Double) {
        self.node = node; self.origin = origin; self.observation = observation; self.source = source
        self.minimumLevel = minimumLevel; self.maximumLevel = maximumLevel; self.elapsed = elapsed
    }
}

/// Contact carries no floor information. Relative intervals require separately justified measurements;
/// none is collected by this checkpoint. All supplied times are in one replay clock domain.
public struct GraphFloorEdge: Sendable {
    public let from, to: UInt64
    public let kind: GraphFloorEdgeKind
    public let minimumDelta, maximumDelta: Int
    public let elapsed: Double
    public init(from: UInt64, to: UInt64, kind: GraphFloorEdgeKind, minimumDelta: Int = 0,
                maximumDelta: Int = 0, elapsed: Double) {
        self.from = from; self.to = to; self.kind = kind
        self.minimumDelta = minimumDelta; self.maximumDelta = maximumDelta; self.elapsed = elapsed
    }
}

public enum GraphFloorReason: Int32, Sendable {
    case noOutput = -1, candidate = 0, noReference, ambiguous, conflict, invalid, limit
    public var message: String {
        switch self {
        case .candidate: "Unvalidated graph candidate"
        case .noReference: "Unknown: no fresh reference path"
        case .ambiguous: "Unknown: multiple levels remain possible"
        case .conflict: "Unknown: contradictory evidence or original identity"
        case .invalid: "Unknown: invalid graph input"
        case .limit: "Unknown: graph exceeds bounded capacity"
        case .noOutput: "Unknown: output unavailable"
        }
    }
}

public struct GraphFloorResult: Sendable {
    public let reason: GraphFloorReason
    public let minimumLevel, maximumLevel: Int?
    public let origins, skipped: Int
    public var level: Int? { reason == .candidate ? minimumLevel : nil }
}

public enum FloorGraph {
    public static func evaluate(nodes: [UInt64], edges: [GraphFloorEdge], observations: [GraphFloorObservation],
                                target: UInt64, now: Double) -> GraphFloorResult {
        // Check counts before copying any caller-sized buffer. The C++ engine also checks its ABI.
        guard nodes.count <= 32, edges.count <= 64, observations.count <= 32 else {
            return GraphFloorResult(reason: .limit, minimumLevel: nil, maximumLevel: nil, origins: 0, skipped: 0)
        }
        let cEdges = edges.map { rc_graph_edge(from: $0.from, to: $0.to, kind: $0.kind.rawValue,
            minimum_delta: Int32(clamping: $0.minimumDelta), maximum_delta: Int32(clamping: $0.maximumDelta), elapsed: $0.elapsed) }
        let cObservations = observations.map { rc_graph_observation(node: $0.node, origin: $0.origin,
            observation: $0.observation, source: $0.source.rawValue, minimum_level: Int32(clamping: $0.minimumLevel),
            maximum_level: Int32(clamping: $0.maximumLevel), elapsed: $0.elapsed) }
        var output = rc_graph_result()
        let code = nodes.withUnsafeBufferPointer { n in cEdges.withUnsafeBufferPointer { e in
            cObservations.withUnsafeBufferPointer { o in
                rc_floor_graph(n.baseAddress, n.count, e.baseAddress, e.count, o.baseAddress, o.count, target, now, &output)
            }
        }}
        let reason = GraphFloorReason(rawValue: code.rawValue) ?? .invalid
        let bounded = reason == .candidate || reason == .ambiguous
        return GraphFloorResult(reason: reason, minimumLevel: bounded ? Int(output.minimum_level) : nil,
                                maximumLevel: bounded ? Int(output.maximum_level) : nil,
                                origins: Int(output.origins), skipped: Int(output.skipped))
    }
}

public enum CooperativeFloorMode: String, CaseIterable, Sendable {
    case sensorOnly = "Sensor baseline", wifi = "Baseline + Wi-Fi", peer = "Baseline + phones", combined = "Combined graph"
}

public struct CooperativeFloorScenario: Sendable {
    public let title, explanation: String
    public let nodes: [UInt64]
    public let edges: [GraphFloorEdge]
    public let observations: [GraphFloorObservation]
    public let target: UInt64
    /// Matched synthetic ablation. Wi-Fi means an explicit surveyed local reference, never just SSID.
    /// Remote reference paths are only present in peer/combined. No statistical accuracy is computed.
    public var results: [CooperativeFloorMode: GraphFloorResult] {
        Dictionary(uniqueKeysWithValues: CooperativeFloorMode.allCases.map { mode in
            let peers = mode == .peer || mode == .combined
            let wifi = mode == .wifi || mode == .combined
            let selected = observations.filter {
                if peers { return wifi || $0.source != .surveyedWiFi }
                return $0.node == target && ($0.source == .sensor || (wifi && $0.source == .surveyedWiFi))
            }
            return (mode, FloorGraph.evaluate(nodes: nodes, edges: peers ? edges : [], observations: selected, target: target, now: 100))
        })
    }
}

public enum CooperativeFloorReplay {
    private static func reference(_ node: UInt64, _ level: Int, _ source: GraphFloorSource = .knownReference,
                                  origin: UInt64 = 10, id: UInt64 = 100, elapsed: Double = 99) -> GraphFloorObservation {
        GraphFloorObservation(node: node, origin: origin, observation: id, source: source,
                              minimumLevel: level, maximumLevel: level, elapsed: elapsed)
    }
    private static let relative = GraphFloorEdge(from: 1, to: 2, kind: .relativeLevel, minimumDelta: 1, maximumDelta: 1, elapsed: 99)
    public static let scenarios: [CooperativeFloorScenario] = [
        .init(title: "Contact is not a floor", explanation: "Phone 1 has reference level 2. Phone 2 can contact it, but may be on another floor. No level constraint is available.", nodes: [1, 2], edges: [.init(from: 1, to: 2, kind: .contact, elapsed: 99)], observations: [reference(1, 2)], target: 2),
        .init(title: "Surveyed Wi-Fi reference", explanation: "A fictional surveyed reference constrains phone 2 to level 2. This is not an eduroam lookup or live AP observation.", nodes: [1, 2], edges: [], observations: [reference(2, 2, .surveyedWiFi)], target: 2),
        .init(title: "Peer with relative constraint", explanation: "Phone 1 has known level 2; an explicitly supplied synthetic measurement puts phone 2 one level above it. Contact alone could not establish this.", nodes: [1, 2], edges: [relative], observations: [reference(1, 2)], target: 2),
        .init(title: "Contradictory references", explanation: "Local sensor says 2; surveyed Wi-Fi reference says 3. Combined output remains Unknown instead of voting away the disagreement.", nodes: [1, 2], edges: [], observations: [reference(2, 2, .sensor), reference(2, 3, .surveyedWiFi, origin: 11, id: 101)], target: 2),
        .init(title: "Forwarded original repeated", explanation: "Two copies retain the same original identity. They contribute one origin, without increasing confidence.", nodes: [1, 2], edges: [relative], observations: [reference(1, 2), reference(1, 2)], target: 2),
        .init(title: "Adjacent floors remain possible", explanation: "The supplied interval permits the same or next level. It cannot support a single-floor candidate.", nodes: [1, 2], edges: [.init(from: 1, to: 2, kind: .relativeLevel, minimumDelta: 0, maximumDelta: 1, elapsed: 99)], observations: [reference(1, 2)], target: 2),
        .init(title: "Expired reference", explanation: "The reference is 11 seconds old at replay time 100. The research freshness limit is 10 seconds, so it cannot anchor the graph.", nodes: [1, 2], edges: [relative], observations: [reference(1, 2, elapsed: 89)], target: 2)
    ]
}
