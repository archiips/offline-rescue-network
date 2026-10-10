import Foundation

/// Enrollment uses one cryptographic identity with an independently owned C++ conversation.
@MainActor protocol EnrollmentConversationContext: AnyObject {
    var role: EndpointRole { get }
    var card: SecurePairingCard { get }
    var peerCard: SecurePairingCard? { get }
    func enrollmentIdentity() throws -> SecureIdentity
    func pair(_ base64: String) throws
    func nextPlaintextPacket() throws -> Data?
    func accept(_ packet: Data) throws -> Data
    func confirm(_ packet: Data) throws
}
extension SecureEndpointController: EnrollmentConversationContext {
    func nextPlaintextPacket() throws -> Data? { try endpoint.nextPacket() }
}
