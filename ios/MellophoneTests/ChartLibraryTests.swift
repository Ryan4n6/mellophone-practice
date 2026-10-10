import XCTest
@testable import Mellophone

/// The charts kept on the device. Every test runs in its own scratch folder,
/// so none of them can see or touch a real chart.
final class ChartLibraryTests: XCTestCase {

    private var scratch: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("charts-\(UUID().uuidString)", isDirectory: true)
        scratch = base.appendingPathComponent("library", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
    }

    private func file(_ name: String, holding text: String = "x") throws -> URL {
        let url = outside.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testAnEmptyLibraryIsEmptyAndDoesNotNeedItsFolderToExist() {
        XCTAssertTrue(ChartLibrary(directory: scratch).charts.isEmpty)
    }

    /// The reason the library exists: the picked address stops working, so the
    /// chart has to still be here after the original is gone.
    func testAddingCopiesTheFileSoItOutlivesTheOriginal() throws {
        let library = ChartLibrary(directory: scratch)
        let source = try file("Show Opener - Horn in F.pdf", holding: "the chart")
        let chart = try library.add(from: source)
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(library.charts.map(\.title), ["Show Opener - Horn in F"])
        XCTAssertEqual(try String(contentsOf: chart.url, encoding: .utf8), "the chart")
        XCTAssertEqual(ChartLibrary(directory: scratch).charts.map(\.title), ["Show Opener - Horn in F"],
                       "a fresh launch has to find it again")
    }

    /// A director fixes a note and exports again under the same name.
    func testTheSameNameReplacesRatherThanPilingUp() throws {
        let library = ChartLibrary(directory: scratch)
        try library.add(from: try file("Opener.pdf", holding: "first"))
        let chart = try library.add(from: try file("Opener.pdf", holding: "corrected"))
        XCTAssertEqual(library.charts.count, 1)
        XCTAssertEqual(try String(contentsOf: chart.url, encoding: .utf8), "corrected")
    }

    /// Adding a chart from inside the library must not delete it on the way to
    /// copying it over itself.
    func testAddingAChartThatIsAlreadyHereKeepsIt() throws {
        let library = ChartLibrary(directory: scratch)
        let chart = try library.add(from: try file("Opener.pdf", holding: "only copy"))
        try library.add(from: chart.url)
        XCTAssertEqual(try String(contentsOf: chart.url, encoding: .utf8), "only copy")
    }

    func testChartsAreListedByNameAndOnlyPDFsCount() throws {
        let library = ChartLibrary(directory: scratch)
        try library.add(from: try file("closer.pdf"))
        try library.add(from: try file("Ballad.PDF"))
        try library.add(from: try file("Opener.pdf"))
        try Data("notes".utf8).write(to: scratch.appendingPathComponent("stray.txt"))
        XCTAssertEqual(ChartLibrary(directory: scratch).charts.map(\.title), ["Ballad", "closer", "Opener"])
    }

    func testRemovingTakesTheCopyAndLeavesTheOriginal() throws {
        let library = ChartLibrary(directory: scratch)
        let source = try file("Opener.pdf")
        let chart = try library.add(from: source)
        library.remove(chart)
        XCTAssertTrue(library.charts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chart.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testAFileThatIsNotThereIsAnErrorAndAddsNothing() {
        let library = ChartLibrary(directory: scratch)
        XCTAssertThrowsError(try library.add(from: outside.appendingPathComponent("gone.pdf")))
        XCTAssertTrue(library.charts.isEmpty)
    }
}
