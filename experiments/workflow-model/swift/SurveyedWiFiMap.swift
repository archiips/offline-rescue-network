import Foundation

public enum SurveyedWiFiMapError: Error { case invalidMap }

/// An unvalidated, device-local handset coverage survey. It grants no network identity authority.
public struct SurveyedWiFiMap: Codable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let campus, building, provenance: String
        public let surveyedAt, expiresAt: Int64
        public let bssid: String
        public let minimumLevel, maximumLevel: Int
        public init(campus: String, building: String, provenance: String, surveyedAt: Int64, expiresAt: Int64,
                    bssid: String, minimumLevel: Int, maximumLevel: Int) {
            self.campus = campus; self.building = building; self.provenance = provenance
            self.surveyedAt = surveyedAt; self.expiresAt = expiresAt; self.bssid = bssid
            self.minimumLevel = minimumLevel; self.maximumLevel = maximumLevel
        }
    }
    public let version: Int
    public let entries: [Entry]
    private enum CodingKeys: String, CodingKey { case version, entries }
    public init(entries: [Entry]) throws {
        self.version = 1; self.entries = entries
        try validate()
        guard try Self.encoder().encode(self).count <= 65536 else { throw SurveyedWiFiMapError.invalidMap }
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        entries = try values.decode([Entry].self, forKey: .entries)
        try validate()
        guard try Self.encoder().encode(self).count <= 65536 else { throw SurveyedWiFiMapError.invalidMap }
    }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    private static func validText(_ text: String, maximum: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= maximum &&
        !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
    private func validate() throws {
        guard version == 1, entries.count <= 128 else { throw SurveyedWiFiMapError.invalidMap }
        var seen: [String: Entry] = [:]
        for entry in entries {
            guard Self.validText(entry.campus, maximum: 128), Self.validText(entry.building, maximum: 128),
                  Self.validText(entry.provenance, maximum: 512), entry.surveyedAt >= 0,
                  entry.expiresAt > entry.surveyedAt, (-20...200).contains(entry.minimumLevel),
                  (-20...200).contains(entry.maximumLevel), entry.minimumLevel <= entry.maximumLevel,
                  let observation = ConnectedWiFiObservation(ssid: "survey", bssid: entry.bssid, capturedAt: 0),
                  observation.bssid == entry.bssid else { throw SurveyedWiFiMapError.invalidMap }
            // Length prefixes prevent collisions between otherwise valid context strings.
            let key = "\(entry.campus.utf8.count):\(entry.campus)\(entry.building.utf8.count):\(entry.building)\(entry.bssid)"
            if let prior = seen[key], prior != entry { throw SurveyedWiFiMapError.invalidMap }
            seen[key] = entry
        }
    }
    public func encoded() throws -> Data {
        try validate()
        let data = try Self.encoder().encode(self)
        guard data.count <= 65536 else { throw SurveyedWiFiMapError.invalidMap }
        return data
    }
    /// Canonical JSON rejects duplicate/unknown keys and noncanonical forms rather than silently rewriting them.
    public static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 65536 else { throw SurveyedWiFiMapError.invalidMap }
        let map = try JSONDecoder().decode(Self.self, from: data)
        try map.validate()
        guard try map.encoded() == data else { throw SurveyedWiFiMapError.invalidMap }
        return map
    }
    public func evidence(observation: ConnectedWiFiObservation, campus: String, building: String,
                         wallTime: Int64, elapsed: Double) -> SurveyedWiFiEvidence? {
        guard observation.isFresh(at: elapsed), wallTime >= 0,
              let entry = entries.first(where: { $0.campus == campus && $0.building == building && $0.bssid == observation.bssid }),
              wallTime >= entry.surveyedAt, wallTime < entry.expiresAt else { return nil }
        // A capture predating the survey is not retroactively evidence for its map window.
        let age = elapsed - observation.capturedAt
        guard Double(wallTime - entry.surveyedAt) >= age else { return nil }
        return SurveyedWiFiEvidence(minimumLevel: entry.minimumLevel, maximumLevel: entry.maximumLevel,
            sampledAt: observation.capturedAt, observation: observation.id, campus: entry.campus,
            building: entry.building, provenance: entry.provenance, surveyedAt: entry.surveyedAt, expiresAt: entry.expiresAt)
    }
}

/// Original local coverage reference. Intentionally contains no SSID/BSSID and is not a peer payload.
public struct SurveyedWiFiEvidence: Equatable, Sendable {
    public let minimumLevel, maximumLevel: Int
    public let sampledAt: Double
    public let observation: UUID
    public var id: UUID { observation }
    public let campus, building, provenance: String
    public let surveyedAt, expiresAt: Int64
}
