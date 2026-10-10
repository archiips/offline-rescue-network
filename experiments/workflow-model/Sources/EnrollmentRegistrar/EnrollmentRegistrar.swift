import Foundation
import CryptoKit
import RescueDemoState

/// Attended synthetic registrar, NOT a production account or campus enrollment service.
/// Only public cards/profiles are file-based; the issuer private key stays in Mac Keychain.
@main struct EnrollmentRegistrar {
    struct IssuerRecord: Codable { let realm: UUID; let key: Data; var revoked: [UUID]? }
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2, args[0] == "revoke" {
            guard let serial = UUID(uuidString: args[1]) else { throw EnrollmentError.malformed }
            let root = URL.applicationSupportDirectory.appendingPathComponent("RescueSyntheticRegistrar")
            let store = DefaultKeychainStore(rootURL: root, role: .responder, namespace: "synthetic-registrar-v1")
            guard let saved = try store.read(), saved.count <= 65536,
                  var record = try? JSONDecoder().decode(IssuerRecord.self, from: saved), record.key.count == 32 else { throw EnrollmentError.malformed }
            var revoked = Set(record.revoked ?? [])
            revoked.insert(serial)
            guard revoked.count <= 64 else { throw EnrollmentError.malformed }
            record.revoked = revoked.sorted { $0.uuidString < $1.uuidString }
            try store.write(JSONEncoder().encode(record))
            print("Synthetic credential revoked for subsequently issued profiles. Already-offline profiles do not update automatically; redistribute fresh profiles before the drill.")
            return
        }
        guard args.count == 3 || args.count == 4,
              args[0] == "public" || args[0] == "responder",
              (args[0] == "public" && args.count == 3) || (args[0] == "responder" && args.count == 4 && args[3] == "--authorize-responder") else {
            throw NSError(domain: "Synthetic registrar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: rescue-enrollment-registrar public REQUEST.txt OUTPUT.json | responder REQUEST.txt OUTPUT.json --authorize-responder. Run only for organizer-approved synthetic drill devices."])
        }
        let requestURL = URL(fileURLWithPath: args[1]), outputURL = URL(fileURLWithPath: args[2])
        let input = try Data(contentsOf: requestURL, options: .mappedIfSafe)
        guard input.count <= 256, let text = String(data: input, encoding: .utf8) else { throw EnrollmentError.malformed }
        let card = try SecurePairingCard(base64: text.trimmingCharacters(in: .whitespacesAndNewlines))
        let role: EndpointRole = args[0] == "public" ? .publicUser : .responder
        guard card.role == role else { throw EnrollmentError.wrongRole }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw CocoaError(.fileWriteFileExists) }
        let root = URL.applicationSupportDirectory.appendingPathComponent("RescueSyntheticRegistrar")
        let store = DefaultKeychainStore(rootURL: root, role: .responder, namespace: "synthetic-registrar-v1")
        let record: IssuerRecord
        if let saved = try store.read() {
            guard saved.count <= 65536, let decoded = try? JSONDecoder().decode(IssuerRecord.self, from: saved), decoded.key.count == 32 else { throw EnrollmentError.malformed }
            record = decoded
        } else {
            record = IssuerRecord(realm: UUID(), key: Curve25519.Signing.PrivateKey().rawRepresentation, revoked: [])
            try store.write(JSONEncoder().encode(record))
        }
        let issuer = try Curve25519.Signing.PrivateKey(rawRepresentation: record.key)
        let now = Int64(Date().timeIntervalSince1970), until = now + 86400
        let credential = try EnrollmentCredential.issue(card: card, realm: record.realm, notBefore: max(0, now - 300), expires: until, issuer: issuer)
        let profile = try EnrollmentProfile.issue(realm: record.realm, issuer: issuer, validUntil: until, credential: credential.bytes, revoked: Set(record.revoked ?? []))
        try profile.encoded().write(to: outputURL, options: .withoutOverwriting)
        print("Synthetic drill profile issued for \(args[0]); expires in 24 hours. Not UW or agency enrollment.")
        print("Credential serial: \(credential.serial.uuidString)")
        print("Compare the entire issuer fingerprint during preparation: \(profile.issuerFingerprint)")
    }
}
