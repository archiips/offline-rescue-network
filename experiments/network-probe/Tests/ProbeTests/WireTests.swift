import Foundation
import Testing
import ProbeWire

@Test func roundTripAndNetworkByteContract() {
    let id = Array(UInt8(0)...UInt8(15))
    var frame = [UInt8](repeating: 0, count: 24)
    #expect(probe_encode(1, id, &frame, frame.count) == 1)
    #expect(frame == [79, 82, 80, 49, 1, 0, 0, 0] + id)
    var kind: UInt8 = 0
    var decoded = [UInt8](repeating: 255, count: 16)
    #expect(probe_decode(frame, frame.count, &kind, &decoded) == 1)
    #expect(kind == 1 && decoded == id)
}

@Test func malformedFramesNeverModifyOutputs() {
    let valid = [UInt8]([79, 82, 80, 49, 2, 0, 0, 0]) + Array(repeating: 42, count: 16)
    var cases = [Array(valid.prefix(23)), valid + [0]]
    for index in 0..<8 {
        var bad = valid
        bad[index] = index == 4 ? 3 : 255
        cases.append(bad)
    }
    for bad in cases {
        var kind: UInt8 = 99
        var id = [UInt8](repeating: 99, count: 16)
        #expect(probe_decode(bad, bad.count, &kind, &id) == 0)
        #expect(kind == 99 && id.allSatisfy { $0 == 99 })
    }
    var kind: UInt8 = 99
    var id = [UInt8](repeating: 99, count: 16)
    #expect(probe_decode(nil, 24, &kind, &id) == 0)
}

@Test func invalidEncodingDoesNotWrite() {
    let id = [UInt8](repeating: 1, count: 16)
    var output = [UInt8](repeating: 99, count: 24)
    #expect(probe_encode(3, id, &output, 24) == 0)
    #expect(probe_encode(1, nil, &output, 24) == 0)
    #expect(probe_encode(1, id, &output, 23) == 0)
    #expect(output.allSatisfy { $0 == 99 })
}
