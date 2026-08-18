import XCTest
@testable import Mellophone

final class PracticeLogTests: XCTestCase {

    /// A fresh, isolated UserDefaults per test so these never touch, or depend
    /// on, whatever is on the machine running them.
    private func makeLog() -> (PracticeLog, UserDefaults, String) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PracticeLog(defaults: defaults), defaults, suite)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testSavesASession() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertTrue(log.save(seconds: 600))
        XCTAssertEqual(log.sessions.count, 1)
        XCTAssertEqual(log.sessions.first?.seconds, 600)
    }

    /// Matches the web version: anything shorter is silently dropped there, and
    /// dropped-but-reported here.
    func testIgnoresSessionsUnderTenSeconds() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertFalse(log.save(seconds: 9))
        XCTAssertTrue(log.sessions.isEmpty)
        XCTAssertTrue(log.save(seconds: 10), "exactly ten seconds should count")
        XCTAssertEqual(log.sessions.count, 1)
    }

    func testNewestFirst() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        log.save(seconds: 100)
        log.save(seconds: 200)
        XCTAssertEqual(log.sessions.map(\.seconds), [200, 100])
    }

    /// The cap the web version uses. The OLDEST entries have to be the ones that
    /// go, which is the easy thing to get backwards.
    func testCapsAtFiftyAndDropsTheOldest() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        for i in 1...60 { log.save(seconds: 10 + i) }
        XCTAssertEqual(log.sessions.count, PracticeLog.maxEntries)
        XCTAssertEqual(log.sessions.first?.seconds, 70, "newest kept")
        XCTAssertEqual(log.sessions.last?.seconds, 21, "oldest ten dropped")
    }

    /// The log has to survive the app being killed, which is the whole point of
    /// writing it down.
    func testSurvivesReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let first = PracticeLog(defaults: defaults)
        first.save(seconds: 300)
        first.save(seconds: 450)

        let second = PracticeLog(defaults: defaults)
        XCTAssertEqual(second.sessions.map(\.seconds), [450, 300])
        XCTAssertEqual(second.totalSeconds, 750)
    }

    func testClearEmptiesIt() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        log.save(seconds: 300)
        log.clear()
        XCTAssertTrue(log.sessions.isEmpty)
        XCTAssertEqual(log.totalSeconds, 0)
    }

    func testTotalAddsUp() {
        let (log, _, suite) = makeLog()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        log.save(seconds: 100)
        log.save(seconds: 250)
        XCTAssertEqual(log.totalSeconds, 350)
    }
}

final class DurationFormattingTests: XCTestCase {

    /// mm:ss, matching the web version's formatTime.
    func testMinutesAndSeconds() {
        XCTAssertEqual(formatDuration(0), "00:00")
        XCTAssertEqual(formatDuration(9), "00:09")
        XCTAssertEqual(formatDuration(65), "01:05")
        XCTAssertEqual(formatDuration(600), "10:00")
    }

    /// The web version would render a long total as an absurd minute count:
    /// three hours of practice reads as "180:00" there.
    func testRollsOverIntoHours() {
        XCTAssertEqual(formatDuration(3600), "1:00:00")
        XCTAssertEqual(formatDuration(3661), "1:01:01")
        XCTAssertEqual(formatDuration(10_800), "3:00:00")
    }
}
