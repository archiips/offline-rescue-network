import Foundation
import SQLite3
import Testing
import RescueDemoBridge
@testable import RescueDemoState

@Test @MainActor func boundEndpointRejectsAuthenticSameShapeDatabaseTransplant() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-bound-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("a.sqlite"), b = root.appendingPathComponent("b.sqlite")
    var aEndpoint: EndpointController? = EndpointController(storageURL: a, role: .responder, storageBinding: "responder:public-A")
    var bEndpoint: EndpointController? = EndpointController(storageURL: b, role: .responder, storageBinding: "responder:public-B")
    let userA = EndpointController(storageURL: root.appendingPathComponent("public-A.sqlite"), role: .publicUser)
    #expect(userA.perform(.sos, value: "Synthetic A"))
    _ = try aEndpoint?.accept(#require(try userA.nextPacket()))
    let user = EndpointController(storageURL: root.appendingPathComponent("public-B.sqlite"), role: .publicUser)
    #expect(user.perform(.sos, value: "Synthetic B"))
    _ = try bEndpoint?.accept(#require(try user.nextPacket()))
    #expect(aEndpoint?.snapshot?.state.reportedLocation == "Synthetic A")
    #expect(bEndpoint?.snapshot?.state.hasRequest == true)
    aEndpoint = nil; bEndpoint = nil
    let intactB = try Data(contentsOf: b)
    try intactB.write(to: a)
    let wrong = EndpointController(storageURL: a, role: .responder, storageBinding: "responder:public-A")
    #expect(wrong.snapshot == nil)
    #expect(try Data(contentsOf: a) == intactB)
    let right = EndpointController(storageURL: b, role: .responder, storageBinding: "responder:public-B")
    #expect(right.snapshot?.state.reportedLocation == "Synthetic B")
    #expect(right.perform(.reply, value: "Synthetic saved reply"))
    right.reopen()
    #expect(right.snapshot?.pendingTransfers == 1)
}

@Test @MainActor func boundEndpointRejectsLegacyEmptyAndMissingBindingsWithoutMutation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-bound-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let legacy = root.appendingPathComponent("legacy.sqlite")
    var old: EndpointController? = EndpointController(storageURL: legacy, role: .responder)
    #expect(old?.snapshot != nil); old = nil
    let legacyBytes = try Data(contentsOf: legacy)
    #expect(EndpointController(storageURL: legacy, role: .responder, storageBinding: "responder:public-A").snapshot == nil)
    #expect(try Data(contentsOf: legacy) == legacyBytes)
    let empty = root.appendingPathComponent("empty.sqlite")
    try Data().write(to: empty)
    #expect(EndpointController(storageURL: empty, role: .responder, storageBinding: "responder:public-A").snapshot == nil)
    #expect(try Data(contentsOf: empty).isEmpty)
    let bound = root.appendingPathComponent("bound.sqlite")
    var endpoint: EndpointController? = EndpointController(storageURL: bound, role: .responder, storageBinding: "responder:public-A")
    #expect(endpoint?.snapshot != nil); endpoint = nil
    let boundBytes = try Data(contentsOf: bound)
    #expect(EndpointController(storageURL: bound, role: .responder).snapshot == nil)
    #expect(EndpointController(storageURL: bound, role: .responder, storageBinding: "").snapshot == nil)
    #expect(EndpointController(storageURL: bound, role: .responder, storageBinding: "bad\0binding").snapshot == nil)
    #expect(EndpointController(storageURL: bound, role: .responder, storageBinding: String(repeating: "x", count: 257)).snapshot == nil)
    #expect(try Data(contentsOf: bound) == boundBytes)
    #expect(rc_endpoint_open_bound(bound.path, 1, nil) == nil)
    #expect(rc_endpoint_open_bound(bound.path, 1, "") == nil)
}

@Test @MainActor func boundEndpointRevalidatesConversationBeforeSaving() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-bound-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("bound.sqlite")
    let endpoint = EndpointController(storageURL: url, role: .responder, storageBinding: "responder:public-A")
    let user = EndpointController(storageURL: root.appendingPathComponent("public.sqlite"), role: .publicUser)
    #expect(user.perform(.sos, value: "Synthetic A"))
    _ = try endpoint.accept(#require(try user.nextPacket()))
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "UPDATE session SET binding='responder:public-B'", nil, nil, nil) == SQLITE_OK)
    #expect(endpoint.perform(.reply, value: "Must not save") == false)
    #expect(endpoint.snapshot?.pendingTransfers == 0)
    #expect(endpoint.snapshot?.state.messages.contains(where: { $0.text == "Must not save" }) == false)
    endpoint.reopen()
    #expect(endpoint.snapshot == nil)
}
