#if canImport(Compression)
import Foundation
import XCTest
@testable import TakaDeCore

final class SyncLimitsTests: XCTestCase {
    private func deflate(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    func testInflateRoundTripsWhatTheAppCompresses() throws {
        let json = Data(String(repeating: #"{"title":"Hotel","total":300000},"#, count: 500).utf8)
        XCTAssertEqual(try BoundedInflate.inflate(try deflate(json), limit: SyncLimits.maxChangeBytes), json)
    }

    func testInflateGrowsItsBufferWhenNeeded() throws {
        // Very repetitive data compresses far more than the first guess allows for.
        let zeros = Data(count: 1_000_000)
        XCTAssertEqual(try BoundedInflate.inflate(try deflate(zeros), limit: SyncLimits.maxChangeBytes), zeros)
    }

    func testInflateRefusesSomethingThatExpandsPastTheLimit() throws {
        let bomb = try deflate(Data(count: 50_000_000))
        XCTAssertLessThan(bomb.count, 100_000)
        XCTAssertThrowsError(try BoundedInflate.inflate(bomb, limit: SyncLimits.maxChangeBytes)) { error in
            XCTAssertTrue(error is BoundedInflate.TooLarge)
        }
    }

    func testInflateRefusesGarbage() {
        XCTAssertThrowsError(try BoundedInflate.inflate(Data(), limit: 1_000))
        XCTAssertThrowsError(try BoundedInflate.inflate(Data([0xFF, 0xFF, 0xFF, 0xFF]), limit: 1_000))
    }

    func testOrdinaryGroupsPassAndHugeOnesDont() {
        let ok = ExpenseGroup(name: "Sylhet trip", members: [Member(displayName: "সাবিত"), Member(displayName: "Rafi")])
        XCTAssertTrue(SyncLimits.accepts(ok))
        var long = ok
        long.members[1].nickname = String(repeating: "r", count: SyncLimits.maxPersonNameLength + 1)
        XCTAssertFalse(SyncLimits.accepts(long))
        var crowded = ok
        crowded.members = (0...SyncLimits.maxMembers).map { Member(displayName: "P\($0)") }
        XCTAssertFalse(SyncLimits.accepts(crowded))
    }
}
#endif
