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

/// Versioned native presentation data inside the existing C++ bounded location field.
public struct LocationReport: Codable, Equatable, Sendable {
    public var reported: String
    public var floor: String
    public var observation: DeviceObservation?
    private static let prefix = "ORLOC1:"
    public init(reported: String, floor: String, observation: DeviceObservation? = nil) {
        self.reported = reported; self.floor = floor; self.observation = observation
    }
    public var title: String { floor.isEmpty ? reported : "\(reported) · \(floor)" }
    private func validate() throws {
        guard !reported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reported.utf8.count <= 512, floor.utf8.count <= 128,
              !reported.contains("\0"), !floor.contains("\0") else { throw LocationReportError.invalidReport }
        try observation?.validate()
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
