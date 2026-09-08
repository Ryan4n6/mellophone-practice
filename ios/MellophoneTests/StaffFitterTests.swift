import XCTest
import CoreGraphics
@testable import Mellophone

/// Real numbers: the MuseScore chart in issue #19 puts its five lines at
/// 360.50, 365.46, 370.42, 375.38 and 380.34, a spacing of 4.96 that is even to
/// within rounding. Those are the values used here.
///
/// Nothing in this file is musical. StaffFitter is pure geometry, which is what
/// lets these tests be written with made-up rectangles instead of a fixture.
final class StaffFitterTests: XCTestCase {

    /// A rule CENTRED on `y`, because a line drawn at y with thickness h spans
    /// y plus or minus h/2. An earlier version of this helper built the rect
    /// with its ORIGIN at y, which put every midY 0.35 points low and made the
    /// asserted line positions wrong rather than the fitter wrong.
    private func rule(y: Double, x0: Double = 50, x1: Double = 500, h: Double = 0.7) -> PlacedPath {
        let r = CGRect(x: x0, y: y - h / 2, width: x1 - x0, height: h)
        return PlacedPath(vertices: [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)],
                          filled: true, bounds: r)
    }

    func testFiveEvenlySpacedRulesBecomeOneSystem() {
        let paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0) }
        let systems = StaffFitter.systems(in: paths)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
        XCTAssertEqual(systems[0].halfSpace, 2.48, accuracy: 0.01)
    }

    func testTwoSystemsOnOnePageAreSeparated() {
        let a = [360.50, 365.46, 370.42, 375.38, 380.34]
        let b = [472.10, 477.06, 482.02, 486.98, 491.94]
        let systems = StaffFitter.systems(in: (a + b).map { rule(y: $0) })
        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
        XCTAssertEqual(systems[1].topLineY, 472.10, accuracy: 0.01)
    }

    /// Four lines is not a staff, and neither is five with a gap in the middle.
    /// Refusing both is what keeps text underlines and bracket lines out of the
    /// result.
    func testRejectsGroupsThatAreNotFiveEvenLines() {
        XCTAssertTrue(StaffFitter.systems(in: [360.5, 365.46, 370.42, 375.38].map { rule(y: $0) }).isEmpty)
        let uneven = [360.5, 365.46, 370.42, 379.0, 384.0].map { rule(y: $0) }
        XCTAssertTrue(StaffFitter.systems(in: uneven).isEmpty)
    }

    /// Sibelius STROKES its staff lines and MuseScore fills them. A stroked line
    /// arrives with bounds of exactly zero height, so a thickness test that
    /// excludes 0, or a filter that requires `filled`, finds no staff at all on
    /// every chart Sam actually owns. Measured on PEAK mello.pdf: 248 stroked
    /// paths against 70 filled, and of the 57 wide thin paths on one page only
    /// 6 are fills.
    func testFindsStrokedStaffLinesAsWellAsFilled() {
        let stroked = [360.50, 365.46, 370.42, 375.38, 380.34].map {
            PlacedPath(vertices: [CGPoint(x: 50, y: $0), CGPoint(x: 500, y: $0)],
                       filled: false,
                       bounds: CGRect(x: 50, y: $0, width: 450, height: 0))
        }
        let systems = StaffFitter.systems(in: stroked)
        XCTAssertEqual(systems.count, 1, "a stroked staff is still a staff")
        XCTAssertEqual(systems[0].topLineY, 360.50, accuracy: 0.01)
    }

    /// A beam is a filled path too, and it is short and thick. Neither it nor a
    /// stem may be mistaken for a staff line.
    func testIgnoresShortAndThickPaths() {
        var paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0) }
        paths.append(rule(y: 362.0, x0: 100, x1: 118, h: 3.5))   // a beam
        paths.append(rule(y: 371.0, x0: 200, x1: 201, h: 24))    // a stem
        let systems = StaffFitter.systems(in: paths)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].lineYs.count, 5)
    }

    /// The x span is the playable width of the system: ScoreBuilder uses it to
    /// decide which glyphs belong to which staff when two systems overlap in y
    /// on a two-part page.
    func testReportsTheHorizontalSpanOfTheSystem() {
        let paths = [360.50, 365.46, 370.42, 375.38, 380.34].map { rule(y: $0, x0: 62, x1: 540) }
        let system = StaffFitter.systems(in: paths).first
        XCTAssertEqual(system?.xRange.lowerBound ?? 0, 62, accuracy: 0.01)
        XCTAssertEqual(system?.xRange.upperBound ?? 0, 540, accuracy: 0.01)
    }

    /// Some engravers emit a fill AND a stroke for the same rule. Ten paths at
    /// five y values must still be one staff: without collapsing them, every
    /// five-wide window contains a zero gap, no window is ever even, and a
    /// perfectly ordinary staff is reported as missing.
    func testTheSameLineDrawnTwiceIsStillOneLine() {
        let ys = [360.50, 365.46, 370.42, 375.38, 380.34]
        let doubled = ys.map { rule(y: $0) } + ys.map { rule(y: $0 + 0.1, h: 0) }
        let systems = StaffFitter.systems(in: doubled)
        XCTAssertEqual(systems.count, 1)
        XCTAssertEqual(systems[0].lineYs.count, 5)
        XCTAssertEqual(systems[0].halfSpace, 2.48, accuracy: 0.05)
    }

    /// The bug the unit tests could not have found, caught by running the fitter
    /// over Sam's actual chart. A multi-measure rest is an H-bar drawn BETWEEN
    /// two staff lines, wide enough to pass a width filter, and PEAK mello.pdf
    /// draws each one twice, once stroked and once filled. Sorting the page by y
    /// and taking every five consecutive rules puts that H-bar in a slot inside
    /// the staff, so its spacing looks uneven and the staff is discarded: 6
    /// systems found on a page that has 9.
    ///
    /// What separates them is the x extent. The five lines of a system are one
    /// set of rectangles and share their ends exactly; the H-bars here are 45 to
    /// 78 points wide against 517.1 for a line.
    func testAnHBarInsideTheStaffDoesNotBreakIt() {
        let lines = [207.76, 212.37, 216.97, 221.58, 226.18].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let hBar = [rule(y: 211.22, x0: 204.7, x1: 268.6, h: 0),
                    rule(y: 211.22, x0: 204.7, x1: 268.6, h: 0)]   // stroked, then filled
        let systems = StaffFitter.systems(in: lines + hBar)
        XCTAssertEqual(systems.count, 1, "the H-bar is not a staff line")
        XCTAssertEqual(systems[0].topLineY, 207.76, accuracy: 0.01)
        XCTAssertEqual(systems[0].halfSpace, 2.303, accuracy: 0.01)
    }

    /// Two H-bars side by side at the same y are two different bars, not one bar
    /// drawn twice. Collapsing on y alone would throw one away, which is why the
    /// duplicate check runs inside an extent group and not across the page.
    func testTwoBarsAtTheSameHeightAreNotDuplicates() {
        let lines = [466.70, 471.31, 475.91, 480.52, 485.13].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let bars = [rule(y: 481.67, x0: 233.0, x1: 284.6, h: 0),
                    rule(y: 481.67, x0: 285.7, x1: 337.3, h: 0)]
        XCTAssertEqual(StaffFitter.systems(in: lines + bars).count, 1)
    }

    /// Systems are reported top to bottom whichever order their extent groups
    /// were discovered in, because ScoreBuilder reads a page in that order.
    func testSystemsComeBackInPageOrder() {
        let indented = [143.13, 147.74, 152.34, 156.95, 161.55].map { rule(y: $0, x0: 92.0, x1: 569.6) }
        let normal = [78.65, 83.26, 87.86, 92.47, 97.07].map { rule(y: $0, x0: 52.5, x1: 569.6) }
        let systems = StaffFitter.systems(in: indented + normal)
        XCTAssertEqual(systems.count, 2, "an indented first system is still a system")
        XCTAssertEqual(systems[0].topLineY, 78.65, accuracy: 0.01)
        XCTAssertEqual(systems[1].topLineY, 143.13, accuracy: 0.01)
    }

    func testNoPathsYieldsNoSystems() {
        XCTAssertTrue(StaffFitter.systems(in: []).isEmpty)
    }
}
