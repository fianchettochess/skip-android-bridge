// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import SkipAndroidBridge

#if !SKIP
final class AssetInputStreamTests: XCTestCase {
    func testBoundedReadsClampAtEndAndCloseOnce() throws {
        let bytes = Data([1, 2, 3, 4, 5])
        var offset = 0
        var requests: [Int] = []
        var closes = 0
        var stream: AssetInputStream? = AssetInputStream(
            remaining: { Int64(bytes.count - offset) },
            read: { count in
                requests.append(count)
                let amount = min(count, 2) // An asset may return a short read.
                let result = bytes.subdata(in: offset..<(offset + amount))
                offset += amount
                return result
            },
            close: { closes += 1 }
        )
        let reader = try XCTUnwrap(stream)
        XCTAssertEqual(try reader.read(upToCount: 4), Data([1, 2]))
        XCTAssertEqual(try reader.read(upToCount: 4), Data([3, 4]))
        XCTAssertEqual(try reader.read(upToCount: 4), Data([5]))
        XCTAssertEqual(try reader.read(upToCount: 4), Data())
        XCTAssertEqual(requests, [4, 3, 1])
        reader.close()
        reader.close()
        XCTAssertEqual(closes, 1)
        XCTAssertThrowsError(try reader.read(upToCount: 1)) { XCTAssertEqual($0 as? AssetInputStream.ReadError, .closed) }
        stream = nil
        XCTAssertEqual(closes, 1)
    }

    func testEmptyAssetNeverCallsUnderlyingRead() throws {
        var reads = 0
        let stream = AssetInputStream(remaining: { 0 }, read: { _ in reads += 1; return nil }, close: {})
        XCTAssertEqual(try stream.read(upToCount: 64), Data())
        XCTAssertEqual(reads, 0)
    }

    func testInvalidCountAndReadFailuresAreExplicit() throws {
        let stream = AssetInputStream(remaining: { 2 }, read: { _ in nil }, close: {})
        for count in [0, -1, AssetInputStream.maximumReadSize + 1] {
            XCTAssertThrowsError(try stream.read(upToCount: count)) { XCTAssertEqual($0 as? AssetInputStream.ReadError, .invalidCount) }
        }
        XCTAssertThrowsError(try stream.read(upToCount: 2)) { XCTAssertEqual($0 as? AssetInputStream.ReadError, .readFailed) }
        let prematureEOF = AssetInputStream(remaining: { 1 }, read: { _ in Data() }, close: {})
        XCTAssertThrowsError(try prematureEOF.read(upToCount: 1)) { XCTAssertEqual($0 as? AssetInputStream.ReadError, .readFailed) }
        let invalidLength = AssetInputStream(remaining: { -1 }, read: { _ in nil }, close: {})
        XCTAssertThrowsError(try invalidLength.read(upToCount: 1)) { XCTAssertEqual($0 as? AssetInputStream.ReadError, .invalidRemainingLength) }
    }

    func testDeinitClosesOpenHandle() {
        var closes = 0
        var stream: AssetInputStream? = AssetInputStream(remaining: { 0 }, read: { _ in nil }, close: { closes += 1 })
        XCTAssertNotNil(stream)
        stream = nil
        XCTAssertEqual(closes, 1)
    }
}
#endif
