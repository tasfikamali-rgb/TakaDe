import XCTest
@testable import TakaDeCore

final class GroupIconTests: XCTestCase {
    func testEnglishNames() {
        XCTAssertEqual(GroupIcon.emoji(for: "Car"), "🚗")
        XCTAssertEqual(GroupIcon.emoji(for: "car pool"), "🚗")
        XCTAssertEqual(GroupIcon.emoji(for: "Rafi's birthday"), "🎂")
        XCTAssertEqual(GroupIcon.emoji(for: "Cox's Bazar trip"), "🏖️")
        XCTAssertEqual(GroupIcon.emoji(for: "Sajek 2026"), "⛰️")
        XCTAssertEqual(GroupIcon.emoji(for: "Office iftar"), "🌙")
        XCTAssertEqual(GroupIcon.emoji(for: "Flatmates"), "🏠")
        XCTAssertEqual(GroupIcon.emoji(for: "Thursday football"), "⚽")
        XCTAssertEqual(GroupIcon.emoji(for: "Trips"), "🧳")
    }

    func testBanglaInEnglishLetters() {
        XCTAssertEqual(GroupIcon.emoji(for: "Biye bari"), "💍")
        XCTAssertEqual(GroupIcon.emoji(for: "Bazar"), "🛒")
        XCTAssertEqual(GroupIcon.emoji(for: "Kacchi gang"), "🍛")
    }

    func testBengaliNames() {
        XCTAssertEqual(GroupIcon.emoji(for: "গাড়ি"), "🚗")
        XCTAssertEqual(GroupIcon.emoji(for: "গাড়ির খরচ"), "🚗")
        XCTAssertEqual(GroupIcon.emoji(for: "কক্সবাজার ট্যুর"), "🏖️")
        XCTAssertEqual(GroupIcon.emoji(for: "ঈদের বাজার"), "🕌")
        XCTAssertEqual(GroupIcon.emoji(for: "বিয়েতে"), "💍")
        XCTAssertEqual(GroupIcon.emoji(for: "মেস"), "🍚")
    }

    func testBengaliEndingsDontCrossWords() {
        // বাসা is home, not বাস (bus).
        XCTAssertEqual(GroupIcon.emoji(for: "বাসা"), "🏠")
        XCTAssertEqual(GroupIcon.emoji(for: "বাস"), "🚌")
    }

    func testWordsMustMatchWhole() {
        XCTAssertNil(GroupIcon.emoji(for: "Cards night"))
        XCTAssertNil(GroupIcon.emoji(for: "Unity"))
        XCTAssertNil(GroupIcon.emoji(for: "Scary"))
    }

    func testTypedEmojiWins() {
        XCTAssertEqual(GroupIcon.emoji(for: "🏸 Thursday"), "🏸")
        XCTAssertEqual(GroupIcon.emoji(for: "Car ❤️"), "❤️")
    }

    func testNoMatchFallsBackToNil() {
        XCTAssertNil(GroupIcon.emoji(for: "Misc"))
        XCTAssertNil(GroupIcon.emoji(for: "Rahim, Karim"))
        XCTAssertNil(GroupIcon.emoji(for: "  "))
        XCTAssertNil(GroupIcon.emoji(for: "#1 2026"))
    }

    func testEveryIconIsASingleCharacter() {
        for (emoji, keys) in GroupIcon.table {
            XCTAssertEqual(emoji.count, 1, emoji)
            XCTAssertFalse(keys.isEmpty, emoji)
            for key in keys { XCTAssertEqual(key, key.lowercased(), key) }
        }
    }
}
