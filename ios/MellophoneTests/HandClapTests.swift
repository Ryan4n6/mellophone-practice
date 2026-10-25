import AVFoundation
import XCTest
@testable import Mellophone

/// Hand claps (#53): x noteheads, read for their rhythm and played as a clap.
///
/// `hand-claps.pdf` is OURS, engraved by MuseScore from
/// `Fixtures/hand-claps.musicxml`, whose header lists every bar. The expected
/// values below are that list, typed from the source the PDF was made from.
/// The same chart drawn as a picture is checked in `RasterReaderTests`, and
/// Sam's ePrint, where it exists, there too.
final class HandClapTests: XCTestCase {

    func testAnXNoteheadIsReadAsAClapWithItsRhythm() throws {
        let score = try fixture()
        let bars = HandClapTests.bars(score)
        XCTAssertEqual(bars[1], ["C5 1", "G4 1", "E4 2"])
        XCTAssertEqual(bars[2], ["clap 1", "clap 1", "clap 1", "rest 1"])
        XCTAssertEqual(bars[3], ["clap 0.5", "clap 0.5", "clap 1", "clap 1.5", "clap 0.5"],
                       "beamed eighths, a dotted quarter and a flagged eighth")
        XCTAssertEqual(bars[4], ["clap 0.5", "clap 0.25", "clap 0.25", "rest 2", "clap 1"],
                       "an eighth and two sixteenths under one beam")
        XCTAssertEqual(bars[5], ["rest 0.5", "clap 0.5", "rest 1", "clap 0.5", "clap 0.5", "rest 1"],
                       "stems up")
        XCTAssertEqual(bars[6], ["clap 0.5", "rest 0.5", "clap 1", "rest 2"])
        XCTAssertEqual(bars[7], ["G4 1", "F4 1", "E4 1", "D4 1"])
        XCTAssertEqual(bars[8], ["C4 4"])
        XCTAssertEqual(score.suspectMeasures, [], "every bar adds up once its claps are read")
    }

    /// A clap is not a note: no pitch to play or check, no fingering, and it
    /// is not a rest either, so it is boxed on the card and counted in time.
    func testAClapHasNoPitchAndIsNotARest() throws {
        let claps = try fixture().events.filter(\.isClap)
        XCTAssertEqual(claps.count, 17)
        for clap in claps {
            XCTAssertNil(clap.note)
            XCTAssertNil(clap.outOfRangeName)
            XCTAssertFalse(clap.isRest)
            XCTAssertNotNil(clap.place, "the card view boxes it")
            XCTAssertNil(Fingering.value(for: clap.writtenName, on: .mellophone))
        }
    }

    // MARK: - Hearing it

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    /// A clap is a short crack with no pitch in it. Measured with the app's
    /// own YIN at a doubt of 0.2, which is checked first against a horn tone
    /// of the same length so a nil from it means "no pitch here" and not
    /// "this detector says nil to everything".
    func testAClapIsAShortCrackWithNoPitch() throws {
        let clap = try XCTUnwrap(ClapSound.render(volume: 0.8, format: format))
        let samples = Self.samples(clap)
        XCTAssertLessThanOrEqual(Double(samples.count) / format.sampleRate, 0.2, "over in a fifth of a second")
        let peakAt = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) }!
        XCTAssertLessThan(Double(peakAt) / format.sampleRate, 0.03, "loudest at the crack, not later")
        XCTAssertGreaterThan(samples.map(abs).max()!, 0.3, "loud enough to hear over nothing")
        XCTAssertLessThan(Self.rms(samples.suffix(samples.count / 5)), 0.02, "and gone by the end")

        let tone = try XCTUnwrap(TonePlayer.render(frequency: 440, duration: 0.2, volume: 0.8, format: format))
        XCTAssertNotNil(Pitch.fundamental(of: Self.samples(tone).map(Double.init), sampleRate: format.sampleRate, doubt: 0.2),
                        "the control: a horn tone has a pitch at this doubt")
        XCTAssertNil(Pitch.fundamental(of: samples.map(Double.init), sampleRate: format.sampleRate, doubt: 0.2),
                     "a clap has none")
    }

    /// Bar 2 at the 100 the fixture prints: claps on 1, 2 and 3, and beat 4
    /// a rest. Heard in the rendered chunk, not taken from the event list.
    func testAPartClapsWhereThePageDoes() throws {
        let timeline = PartTimeline(score: try fixture(), voice: .line(0), measures: 2...2, bpm: 100,
                                    sounding: .mellophone)
        let chunk = try XCTUnwrap(timeline.chunks(sampleRate: format.sampleRate).first)
        XCTAssertEqual(chunk.events.filter(\.isClap).map { ($0.onset * 1000).rounded() }, [0, 600, 1200])
        let samples = Self.samples(try XCTUnwrap(PartPlayer.render(chunk, volume: 0.5, format: format)))
        func loudness(_ from: Double, _ to: Double) -> Double {
            Self.rms(Array(samples[Int(from * format.sampleRate)..<Int(to * format.sampleRate)]))
        }
        for beat in 0..<3 {
            XCTAssertGreaterThan(loudness(Double(beat) * 0.6, Double(beat) * 0.6 + 0.05), 0.05, "a clap on beat \(beat + 1)")
        }
        XCTAssertLessThan(loudness(1.85, 2.4), 0.001, "beat 4 is a rest")
    }

    /// A clap is a clap on any horn: the part moves to the pitch the selected
    /// horn makes, and the claps in it do not move with it.
    func testAClapSoundsTheSameOnEveryHorn() throws {
        let score = try fixture()
        func bar2(_ instrument: Instrument) throws -> [Float] {
            let timeline = PartTimeline(score: score, voice: .line(0), measures: 2...2, bpm: 100, sounding: instrument)
            let chunk = try XCTUnwrap(timeline.chunks(sampleRate: format.sampleRate).first)
            return Self.samples(try XCTUnwrap(PartPlayer.render(chunk, volume: 0.5, format: format)))
        }
        XCTAssertGreaterThan(Self.rms(try bar2(.mellophone)), 0.01, "there are claps to compare")
        XCTAssertEqual(try bar2(.mellophone), try bar2(.trumpet))
        XCTAssertEqual(try bar2(.mellophone), try bar2(.euphonium))
    }

    // MARK: - Helpers

    private static func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private static func rms(_ samples: some Collection<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count)).squareRoot()
    }

    private func fixture() throws -> Score {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hand-claps", withExtension: "pdf"),
                                "hand-claps.pdf is not in the test bundle")
        return try ScoreImporter.readOrThrow(url: url)
    }

    /// Each bar as "name beats", "clap beats" or "rest beats", in order.
    static func bars(_ score: Score) -> [Int: [String]] {
        var bars: [Int: [String]] = [:]
        for event in score.events {
            let beats = (event.durationBeats * 1000).rounded() / 1000
            let length = beats == beats.rounded() ? "\(Int(beats))" : "\(beats)"
            let name = event.isClap ? "clap" : event.isRest ? "rest" : event.writtenName
            bars[event.measure, default: []].append("\(name) \(length)")
        }
        return bars
    }
}
