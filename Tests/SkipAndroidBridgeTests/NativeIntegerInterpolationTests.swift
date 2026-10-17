// Copyright 2026 Skip
// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import SkipAndroidBridge

#if !SKIP
final class NativeIntegerInterpolationTests: XCTestCase {
    func testNativeUnsignedWordRetainsItsFullWidth() {
        for value in [UInt.zero, UInt.max] {
            var interpolation = AndroidStringInterpolation(literalCapacity: 0, interpolationCount: 1)
            interpolation.appendInterpolation(value)
            XCTAssertEqual(interpolation.pattern, "%llu")
            XCTAssertEqual(interpolation.values.count, 1)
            XCTAssertTrue(type(of: interpolation.values[0]) == UInt64.self)
            XCTAssertEqual(interpolation.values[0] as? UInt64, UInt64(value))
        }
    }

    func testNativeSignedWordRetainsItsFullWidth() {
        for value in [Int.min, Int.zero, Int.max] {
            var interpolation = AndroidStringInterpolation(literalCapacity: 0, interpolationCount: 1)
            interpolation.appendInterpolation(value)
            XCTAssertEqual(interpolation.pattern, "%lld")
            XCTAssertTrue(type(of: interpolation.values[0]) == Int64.self)
            XCTAssertEqual(interpolation.values[0] as? Int64, Int64(value))
        }
    }

    func testExplicitUnsigned64ValuesArePreserved() {
        for value in [UInt64.zero, UInt64.max] {
            var interpolation = AndroidStringInterpolation(literalCapacity: 0, interpolationCount: 1)
            interpolation.appendInterpolation(value)
            XCTAssertEqual(interpolation.pattern, "%llu")
            XCTAssertTrue(type(of: interpolation.values[0]) == UInt64.self)
            XCTAssertEqual(interpolation.values[0] as? UInt64, value)
        }
    }

    func testSignedAndStringArgumentsStayOrdered() {
        var interpolation = AndroidStringInterpolation(literalCapacity: 12, interpolationCount: 2)
        interpolation.appendLiteral("Value ")
        interpolation.appendInterpolation(Int64.min)
        interpolation.appendLiteral(" ")
        interpolation.appendInterpolation("tail")
        XCTAssertEqual(interpolation.pattern, "Value %lld %@")
        XCTAssertEqual(interpolation.values[0] as? Int64, Int64.min)
        XCTAssertEqual(interpolation.values[1] as? String, "tail")
    }
}
#endif
