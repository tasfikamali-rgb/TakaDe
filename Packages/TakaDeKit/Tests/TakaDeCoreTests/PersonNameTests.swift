import XCTest
@testable import TakaDeCore

final class PersonNameTests: XCTestCase {
    func testAcceptsProperNamesInAnyScript() {
        for name in ["Sabit", "Tasfi Kamali", "সাবিত", "মোঃ রফিক", "Nur-E-Alam", "O'Brien", "Md. Rahim",
                     "D’Souza", "José", "Zoë", "李小龙", "محمد", "ক্ষমা", "র‍্যাব"] {
            XCTAssertNil(PersonName.problem(with: name), name)
        }
    }

    func testRejectsEmojiAndSymbols() {
        for name in ["Sabit 😀", "🔥", "❤️", "Rafi ✨", "#1", "Rafi 2", "a+b", "@sabit", "👍🏽", "Sabit ☺️", "1️⃣"] {
            XCTAssertEqual(PersonName.problem(with: name), .notAName, name)
        }
    }

    func testRejectsEmptyAndPunctuationOnly() {
        XCTAssertEqual(PersonName.problem(with: "   "), .empty)
        XCTAssertEqual(PersonName.problem(with: "..."), .notAName)
        XCTAssertEqual(PersonName.problem(with: "-"), .notAName)
    }

    func testRejectsVeryLongNames() {
        XCTAssertEqual(PersonName.problem(with: String(repeating: "a", count: PersonName.maxLength + 1)), .tooLong)
        XCTAssertNil(PersonName.problem(with: String(repeating: "a", count: PersonName.maxLength)))
    }

    func testTrimsOnlyForChecking() {
        XCTAssertNil(PersonName.problem(with: "  Sabit  "))
    }
}
