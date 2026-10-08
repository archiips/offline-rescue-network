import Foundation
public struct DemoSnapshot: Decodable, Sendable {
    public let connected: Bool
    public let pendingTransfers: Int
    public let error: String
    public let publicState: DeviceSnapshot
    public let responderState: DeviceSnapshot
}
public struct DeviceSnapshot: Decodable, Sendable {
    public let hasRequest: Bool
    public let reportedLocation: String
    public let originalDelivery: DemoDelivery
    public let handling: DemoHandling
    public let assignedTo: String
    public let reason: String
    public let withdrawalPending: Bool
    public let withdrawalDisposition: String
    public let lateUpdate: Bool
    public let pendingPublicMessages: Int
    public let messages: [MessageSnapshot]
}
public struct MessageSnapshot: Decodable, Sendable, Identifiable {
    public let id: String
    public let kind: DemoMessageKind
    public let text: String
    public let location: String
    public let reference: String
    public let outgoing: Bool
    public let delivery: DemoDelivery
}
public enum DemoAction: Int, Sendable {
    case sos, followUp, correction, withdrawal, acknowledge, reply, assign, resolve, reopen, disposition
}

// Stable internal snapshot schema. C++ compile-time assertions pin these values.
public enum DemoDelivery: Int, Decodable, Sendable {
    case waiting = 0, deviceReceived = 1, humanAcknowledged = 2
}
public enum DemoHandling: Int, Decodable, Sendable {
    case open = 0, assigned = 1, resolved = 2
}
public enum DemoMessageKind: Int, Decodable, Sendable {
    case request = 0, followUp = 1, correction = 2, withdrawal = 3, receipt = 4,
         acknowledgment = 5, reply = 6, assignment = 7, resolution = 8,
         reopen = 9, withdrawalDisposition = 10
    public var isPublicUpdate: Bool {
        switch self { case .request, .followUp, .correction, .withdrawal: true; default: false }
    }
}
