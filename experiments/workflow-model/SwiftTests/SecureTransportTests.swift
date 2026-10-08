import Foundation
import Testing
@testable import RescueDemoState

@Test func secureFrameFitsEnvelopeButDefaultStaysStrict() throws {
    let payload = Data(repeating: 0x5a, count: 4276)
    #expect(throws: ExchangeFrameError.self) { try ExchangeFrameAccumulator.frame(payload) }
    let framed = try ExchangeFrameAccumulator.frame(payload, maximumPayload: 4276)
    var secure = ExchangeFrameAccumulator(maximumPayload: 4276)
    #expect(try secure.append(Data(framed.prefix(3))) == nil)
    #expect(try secure.append(Data(framed.dropFirst(3))) == payload)
    var plain = ExchangeFrameAccumulator()
    #expect(throws: ExchangeFrameError.self) { try plain.append(framed) }
    #expect(throws: ExchangeFrameError.self) { try ExchangeFrameAccumulator.frame(Data(repeating: 1, count: 4277), maximumPayload: 4276) }
    var over = ExchangeFrameAccumulator(maximumPayload: 4276)
    #expect(throws: ExchangeFrameError.self) { try over.append(Data([0,0,0x10,0xb5])) }
    #expect(over.bufferedCount == 0)
}

@Test @MainActor func secureTransportCarriesFullBoundOverRealSocket() async throws {
    let left = LocalExchangeTransport(secure: true)
    let right = LocalExchangeTransport(secure: true)
    right.onIncoming = { $0 }
    try left.start(name: "Secure bound sender", advertise: false, browse: false)
    try right.start(name: "Secure bound receiver", advertise: false, browse: false)
    defer { left.stop(); right.stop() }
    let deadline = ContinuousClock.now + .seconds(5)
    while right.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Listener not ready"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    let data = Data(repeating: 0x5a, count: 4276)
    let response = try await left.exchange(data, to: .hostPort(host: "127.0.0.1", port: try #require(right.hostPort)))
    #expect(response == data)
}
