import XCTest
@testable import TakaDeCore

final class AmountExpressionTests: XCTestCase {
    func eval(_ s: String) throws -> Int64 { try AmountExpression.evaluate(s).minorUnits }

    func testBasicArithmetic() throws {
        XCTAssertEqual(try eval("1200÷4"), 300_00)
        XCTAssertEqual(try eval("1200 / 4"), 300_00)
        XCTAssertEqual(try eval("450+120.50"), 570_50)
        XCTAssertEqual(try eval("250×1.5"), 375_00)
        XCTAssertEqual(try eval("1000−250"), 750_00)
        XCTAssertEqual(try eval("১২০০÷৪"), 300_00)
        XCTAssertEqual(try eval("1,200"), 1200_00)
    }

    func testPrecedence() throws {
        XCTAssertEqual(try eval("100+200×3"), 700_00)
        XCTAssertEqual(try eval("1000-600÷3"), 800_00)
    }

    func testRoundsOnceHalfUp() throws {
        XCTAssertEqual(try eval("100÷3"), 33_33)
        XCTAssertEqual(try eval("200÷3"), 66_67)
        XCTAssertEqual(try eval("0.125×1"), 13)
    }

    func testTrailingOperatorIsIgnoredWhileTyping() throws {
        XCTAssertEqual(try eval("1200÷"), 1200_00)
    }

    func testErrors() {
        XCTAssertThrowsError(try eval(""))
        XCTAssertThrowsError(try eval("÷4"))
        XCTAssertThrowsError(try eval("5÷0")) { XCTAssertEqual($0 as? AmountExpression.EvaluationError, .divisionByZero) }
        XCTAssertThrowsError(try eval("5-10")) { XCTAssertEqual($0 as? AmountExpression.EvaluationError, .negativeResult) }
        XCTAssertThrowsError(try eval("1..2"))
        XCTAssertThrowsError(try eval("12a"))
    }
}
