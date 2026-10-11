import Foundation

public enum LocationReportError: Error { case invalidObservation, invalidReport }

/// An observation at a particular time, never a live position or a reported floor.
public struct DeviceObservation: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double
    public let observedAt: Date
    public let approximate: Bool

    private var valid: Bool {
        latitude.isFinite && longitude.isFinite && accuracy.isFinite && observedAt.timeIntervalSince1970.isFinite
        && (-90...90).contains(latitude) && (-180...180).contains(longitude) && accuracy >= 0
    }
    public static func capture(latitude: Double, longitude: Double, accuracy: Double, observedAt: Date, approximate: Bool, now: Date = Date()) throws -> Self {
        let observation = Self(latitude: latitude, longitude: longitude, accuracy: accuracy, observedAt: observedAt, approximate: approximate)
        let age = now.timeIntervalSince(observedAt)
        guard observation.valid, age >= -5, age <= 60 else { throw LocationReportError.invalidObservation }
        return observation
    }
    fileprivate func validate() throws { guard valid else { throw LocationReportError.invalidObservation } }
    public var detail: String {
        String(format: "%.5f, %.5f · ±%.0f m%@", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude, accuracy, approximate ? " · approximate" : "")
        + "\nObserved " + observedAt.formatted(date: .abbreviated, time: .standard) + " " + (TimeZone.current.abbreviation(for: observedAt) ?? "") + " · Core Location · not live"
    }
}

public enum EstimatedFloorSource: String, Codable, Equatable, Sendable {
    case appleFloor, relativeAltitude, surveyedWiFi, combinedGraph
}

/// A dated experimental estimate, independent of the person's reported building/floor.
public struct EstimatedFloorObservation: Codable, Equatable, Sendable {
    public let level: Int
    public let source: EstimatedFloorSource
    public let observedAt: Date
    public let context: String?

    fileprivate func validate() throws {
        guard (-20...200).contains(level), observedAt.timeIntervalSince1970.isFinite else {
            throw LocationReportError.invalidObservation
        }
        if let context {
            guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  context.utf8.count <= 256,
                  !context.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
                throw LocationReportError.invalidObservation
            }
        }
    }
    public static func capture(level: Int, source: EstimatedFloorSource, observedAt: Date,
                               context: String? = nil, now: Date = Date()) throws -> Self {
        let value = Self(level: level, source: source, observedAt: observedAt, context: context)
        try value.validate()
        let age = now.timeIntervalSince(observedAt)
        guard now.timeIntervalSince1970.isFinite, age.isFinite, age >= 0, age <= 10 else {
            throw LocationReportError.invalidObservation
        }
        return value
    }
    public var detail: String {
        "Estimated logical level \(level) · \(source.rawValue) · unvalidated"
        + (context.map { " · " + $0 } ?? "")
        + "\nObserved " + observedAt.formatted(date: .abbreviated, time: .standard)
        + " " + (TimeZone.current.abbreviation(for: observedAt) ?? "") + " · not live"
    }
}

extension EstimatedFloorObservation {
    private enum CodingKeys: String, CodingKey { case level, source, observedAt, context }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(level: try values.decode(Int.self, forKey: .level),
                  source: try values.decode(EstimatedFloorSource.self, forKey: .source),
                  observedAt: try values.decode(Date.self, forKey: .observedAt),
                  context: try values.decodeIfPresent(String.self, forKey: .context))
        try validate()
    }
}

/// Versioned native presentation data inside the existing C++ bounded location field.
public struct LocationReport: Codable, Equatable, Sendable {
    public var reported: String
    public var floor: String
    public var observation: DeviceObservation?
    public var estimatedFloor: EstimatedFloorObservation?
    private static let prefix = "ORLOC1:"
    public init(reported: String, floor: String, observation: DeviceObservation? = nil, estimatedFloor: EstimatedFloorObservation? = nil) {
        self.reported = reported; self.floor = floor; self.observation = observation; self.estimatedFloor = estimatedFloor
    }
    public var title: String { floor.isEmpty ? reported : "\(reported) · \(floor)" }
    private func validate() throws {
        guard !reported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reported.utf8.count <= 512, floor.utf8.count <= 128,
              !reported.contains("\0"), !floor.contains("\0") else { throw LocationReportError.invalidReport }
        try observation?.validate()
        try estimatedFloor?.validate()
    }
    public func encoded() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let value = Self.prefix + String(decoding: try encoder.encode(self), as: UTF8.self)
        guard value.utf8.count <= 1800 else { throw LocationReportError.invalidReport }
        return value
    }
    public static func display(_ value: String) -> Self {
        guard value.hasPrefix(prefix) else { return Self(reported: value, floor: "") }
        guard value.utf8.count <= 1800,
              let report = try? JSONDecoder().decode(Self.self, from: Data(value.dropFirst(prefix.count).utf8)),
              (try? report.validate()) != nil else { return Self(reported: "Location report unavailable", floor: "") }
        return report
    }
}
