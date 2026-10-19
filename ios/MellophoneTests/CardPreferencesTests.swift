import XCTest
@testable import Mellophone

/// What the card view remembers (#43). Preferences is one shared object read
/// from the device's defaults once, so its rules for a stored value are
/// tested here as the functions it calls.
final class CardPreferencesTests: XCTestCase {

    func testMusicIsTheDefaultView() {
        XCTAssertEqual(PartViewMode(stored: nil), .music)
        XCTAssertEqual(PartViewMode(stored: "names"), .names)
        XCTAssertEqual(PartViewMode(stored: "music"), .music)
        XCTAssertEqual(PartViewMode(stored: "staff"), .music, "a value this build does not know")
    }

    func testFourLinesToACardByDefaultAndTwoToFourAllowed() {
        XCTAssertEqual(Preferences.cardLines(stored: nil), 4)
        XCTAssertEqual(Preferences.cardLines(stored: 3), 3)
        XCTAssertEqual(Preferences.cardLines(stored: 7), 4)
        XCTAssertEqual(Preferences.cardLines(stored: 1), 2)
    }
}
