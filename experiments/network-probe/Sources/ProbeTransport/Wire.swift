import Foundation
import ProbeWire

public enum Wire {
    public static func encode(kind: UInt8, id: [UInt8]) -> Data? {
        guard id.count == 16 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard probe_encode(kind, id, &bytes, bytes.count) == 1 else { return nil }
        return Data(bytes)
    }
    public static func decode(_ data: Data) -> (kind: UInt8, id: [UInt8])? {
        var kind: UInt8 = 0
        var id = [UInt8](repeating: 0, count: 16)
        let bytes = [UInt8](data)
        guard probe_decode(bytes, bytes.count, &kind, &id) == 1 else { return nil }
        return (kind, id)
    }
}
