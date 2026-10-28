import XCTest
import SwiftUI
@testable import Mellophone

/// The text follows the phone's text size setting (#66).
///
/// Until #66 every font in the app was a fixed point size, and the app drew
/// the same picture at the default size and at the largest accessibility
/// size. Nothing else would notice that coming back: a fixed size renders,
/// lays out and passes every other test. So the sources are read, the way
/// `testflight.sh` reads the binary for networking symbols.
final class TextSizeTests: XCTestCase {

    /// The app's Swift sources, found from this file: the simulator can read
    /// the Mac's disk.
    private func appSources() throws -> [(name: String, text: String)] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let app = tests.deletingLastPathComponent().appendingPathComponent("Mellophone")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 50, "found the app's sources at \(app.path)")
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Every `.font(.system(size:))` goes through `scaledFont`, except text
    /// sized from a drawn shape (a valve's number fits its circle) and the
    /// helper itself.
    func testNoScreenUsesAFixedFontSize() throws {
        let allowed: [String: Int] = [
            "Theme.swift": 1,      // ScaledFont applies the scaled size
            "ValveView.swift": 2,  // the numbers inside the valve circles
            "PartView.swift": 1,   // the + and - symbols, sized from their round button
        ]
        var found: [String: Int] = [:]
        for (name, text) in try appSources() {
            let count = text.components(separatedBy: ".font(.system(size: ").count - 1
            if count > 0 { found[name] = count }
        }
        XCTAssertEqual(found, allowed, "a fixed font size is back; use .scaledFont(size, weight)")
    }

    /// Each size scales on the curve of the text style nearest it.
    func testEachSizeScalesLikeTheNearestTextStyle() {
        XCTAssertEqual(ScaledFont.style(for: 12), .caption)
        XCTAssertEqual(ScaledFont.style(for: 13), .footnote)
        XCTAssertEqual(ScaledFont.style(for: 15), .subheadline)
        XCTAssertEqual(ScaledFont.style(for: 17), .body)
        XCTAssertEqual(ScaledFont.style(for: 22), .title2)
        XCTAssertEqual(ScaledFont.style(for: 42), .largeTitle)
        XCTAssertEqual(ScaledFont.style(for: 9), .caption2)
    }
}
