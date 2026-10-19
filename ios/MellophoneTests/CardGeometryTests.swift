import XCTest
@testable import Mellophone

/// Where things land on a card on the screen (#43): the strips, the box on a
/// note, and what a tap hits. On our own two page fixture.
final class CardGeometryTests: XCTestCase {

    private var score: Score!
    private var geometry: CardGeometry!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "card-turns", withExtension: "pdf"))
        score = try ScoreImporter.readOrThrow(url: url)
        let card = try XCTUnwrap(LyreCards.cards(score.systems, linesPerCard: 4).first)
        geometry = CardGeometry(systems: score.systems, card: card, width: 750)
    }

    private var cardEvents: [ScoreEvent] {
        score.events.filter { $0.place.map { (0..<4).contains($0.system) } ?? false }
    }

    func testStripsStackWithNoGap() {
        XCTAssertEqual(geometry.stripFrame(1).minY, geometry.stripFrame(0).maxY, accuracy: 0.001)
        XCTAssertEqual(geometry.stripFrame(3).minY, geometry.stripFrame(2).maxY, accuracy: 0.001)
        XCTAssertEqual(geometry.height, geometry.stripFrame(3).maxY, accuracy: 0.001)
        XCTAssertEqual(geometry.stripFrame(0).minY, 0, accuracy: 0.001)
    }

    /// The widest line fills the card's width.
    func testTheWidestStripFillsTheWidth() {
        let widest = (0..<4).map { geometry.stripFrame($0).width }.max()!
        XCTAssertEqual(widest, 750, accuracy: 0.001)
    }

    func testABoxSitsOnItsNotehead() throws {
        for event in cardEvents where !event.isRest {
            let place = try XCTUnwrap(event.place)
            let hs = score.systems[place.system].halfSpace
            let box = geometry.box(place)
            XCTAssertTrue(box.contains(geometry.point(x: place.x + 1.2 * hs, y: place.y, system: place.system)),
                          "the box misses \(event.writtenName) in bar \(event.measure)")
            XCTAssertTrue(geometry.stripFrame(place.system).contains(box),
                          "the box for \(event.writtenName) in bar \(event.measure) leaves its strip")
        }
    }

    /// PDF y runs up and the screen's runs down: a higher note is higher up.
    func testAHigherNoteIsHigherOnTheScreen() throws {
        let bar1 = cardEvents.filter { $0.measure == 1 && !$0.isRest }
        let f4 = try XCTUnwrap(bar1.first { $0.writtenName == "F4" }?.place)
        let c5 = try XCTUnwrap(bar1.first { $0.writtenName == "C5" }?.place)
        XCTAssertLessThan(geometry.box(c5).midY, geometry.box(f4).midY)
    }

    func testTappingANoteFindsIt() throws {
        for event in cardEvents where !event.isRest {
            let box = geometry.box(try XCTUnwrap(event.place))
            XCTAssertEqual(geometry.note(at: CGPoint(x: box.midX, y: box.midY), among: cardEvents)?.id, event.id,
                           "a tap on \(event.writtenName) in bar \(event.measure) missed it")
        }
    }

    /// The half notes of bar 4 are far apart; a tap halfway between them is a
    /// tap on the staff, not on a note.
    func testATapBetweenFarApartNotesFindsNothing() throws {
        let bar4 = cardEvents.filter { $0.measure == 4 && !$0.isRest }.sorted { $0.place!.x < $1.place!.x }
        XCTAssertEqual(bar4.count, 2)
        let a = geometry.box(bar4[0].place!), b = geometry.box(bar4[1].place!)
        XCTAssertNil(geometry.note(at: CGPoint(x: (a.midX + b.midX) / 2, y: a.midY), among: cardEvents))
    }

    func testUnplacedNotesAreNotTargets() throws {
        let event = try XCTUnwrap(cardEvents.first { !$0.isRest })
        let box = geometry.box(try XCTUnwrap(event.place))
        var unplaced = event
        unplaced.place = nil
        XCTAssertNil(geometry.note(at: CGPoint(x: box.midX, y: box.midY), among: [unplaced]))
    }

    func testTappingABarFindsItsMeasure() {
        for index in 0..<4 {
            let frame = geometry.stripFrame(index)
            for bar in score.systems[index].bars {
                let x = geometry.point(x: (bar.x0 + bar.x1) / 2, y: score.systems[index].bottomLineY, system: index).x
                XCTAssertEqual(geometry.measure(at: CGPoint(x: x, y: frame.midY)), bar.measure)
            }
        }
    }

    /// A suspect bar is marked on the card, the way the list marks it (#43):
    /// one frame per line the bar is on, over the whole bar.
    func testABarIsFramedWhereItSits() throws {
        let frames = geometry.barFrames([5])
        XCTAssertEqual(frames.count, 1)
        let frame = try XCTUnwrap(frames.first)
        let bar = try XCTUnwrap(score.systems[1].bars.first { $0.measure == 5 })
        XCTAssertEqual(frame.minX, geometry.point(x: bar.x0, y: 0, system: 1).x, accuracy: 0.001)
        XCTAssertEqual(frame.maxX, geometry.point(x: bar.x1, y: 0, system: 1).x, accuracy: 0.001)
        XCTAssertEqual(frame.minY, geometry.stripFrame(1).minY, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, geometry.stripFrame(1).maxY, accuracy: 0.001)
        XCTAssertTrue(geometry.barFrames([99]).isEmpty)
    }
}
