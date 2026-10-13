import AVFoundation
import XCTest
@testable import Mellophone

/// The note check (#22): what the horn should sound, what to say about what
/// it did sound, and whether the listening half can hear the difference.
///
/// What is real here and what is not. The pitches are judged by the shipping
/// detector, and where a tone is needed it is rendered by the app's own
/// `TonePlayer`, at the pitch a real instrument would produce. The verdict
/// tests feed numbers straight in, which proves the arithmetic. NOTHING in
/// this file opens a microphone: a simulator has no horn in front of it, so
/// the session switch is exercised and the listening itself is not.
final class NoteCheckTests: XCTestCase {

    private func check(_ name: String, on instrument: Instrument = .mellophone) throws -> NoteCheck {
        NoteCheck(writtenName: name, writtenFrequency: try XCTUnwrap(Note.named(name)).frequency,
                  instrument: instrument)
    }

    // MARK: - What the horn sounds

    /// Published facts, not the app's own numbers read back: an F instrument
    /// sounds a perfect fifth under what is written and a Bb trumpet a major
    /// second under. Written C5 is concert F4 on a mellophone or a horn and
    /// concert Bb4 on a trumpet, and those two pitches are 349.23 and 466.16
    /// Hz in equal temperament at A440.
    func testAWrittenNoteSoundsAFifthLowerOnAnFInstrumentAndATonelowerOnATrumpet() throws {
        XCTAssertEqual(try check("C5", on: .mellophone).soundingFrequency, 349.23, accuracy: 0.01)
        XCTAssertEqual(try check("C5", on: .frenchHorn).soundingFrequency, 349.23, accuracy: 0.01)
        XCTAssertEqual(try check("C5", on: .trumpet).soundingFrequency, 466.16, accuracy: 0.01)
        XCTAssertEqual(try check("C5", on: .mellophone).soundingName, "F4")
        XCTAssertEqual(try check("C5", on: .trumpet).soundingName, "Bb4")
        // Concert pitch is named in flats.
        XCTAssertEqual(try check("Ab4", on: .mellophone).soundingName, "Db4")
    }

    /// A euphonium reading treble clef sounds a major ninth under the page:
    /// written C5 is the Bb below middle C, 233.08 Hz, and the bottom of the
    /// horn, written F#3, is the E at the bottom of a bass guitar, 82.41 Hz.
    func testAWrittenNoteSoundsANinthLowerOnAEuphonium() throws {
        XCTAssertEqual(try check("C5", on: .euphonium).soundingFrequency, 233.08, accuracy: 0.01)
        XCTAssertEqual(try check("C5", on: .euphonium).soundingName, "Bb3")
        XCTAssertEqual(try check("F#3", on: .euphonium).soundingFrequency, 82.41, accuracy: 0.01)
        XCTAssertEqual(try check("F#3", on: .euphonium).soundingName, "E2")
        // And back: that Bb heard is a written C5 here and a written C4 on a
        // trumpet, whose C5 is an octave above it.
        XCTAssertEqual(try check("C5", on: .euphonium).writtenName(ofHeard: 233.08), "C5")
        XCTAssertEqual(try check("C5", on: .trumpet).writtenName(ofHeard: 233.08), "C4")
    }

    /// The mistake this feature was one line away from. The app plays written
    /// C5 as 523 Hz. A mellophone playing C5 perfectly puts 349 Hz into the
    /// microphone. Judged against the app's own number, a correct note would
    /// be called a fifth flat every time.
    func testAHornPlayingTheNoteCorrectlyIsInTuneAndTheAppsOwnPitchIsNot() throws {
        let c5 = try check("C5")
        guard case .inTune = c5.verdict(heard: 349.23) else {
            return XCTFail("a mellophone's C5 is 349 Hz and was judged \(c5.verdict(heard: 349.23))")
        }
        // 523 Hz through a mellophone's transposition is written G5.
        XCTAssertEqual(c5.verdict(heard: c5.writtenFrequency),
                       .wrongNote(writtenName: "G5", sameValves: true, tooHigh: true))
    }

    // MARK: - What it says

    func testInsideTwentyCentsIsInTuneAndPastItIsFlatOrSharpByThatMuch() throws {
        let c5 = try check("C5")
        let target = c5.soundingFrequency
        func off(_ cents: Double) -> Double { target * pow(2, cents / 1200) }

        // Not 20.0 itself: 20 cents up and back down through pow and log2
        // comes out as 20.000000000000068, and which side of the line that
        // falls is not something a student or this test should care about.
        for cents in [-19.9, -7, 0, 12, 19.9] {
            guard case .inTune = c5.verdict(heard: off(cents)) else {
                XCTFail("\(cents) cents should be in tune, got \(c5.verdict(heard: off(cents)))"); continue
            }
        }
        guard case .flat(let low) = c5.verdict(heard: off(-33)) else { return XCTFail("-33 cents is flat") }
        XCTAssertEqual(low, 33, accuracy: 0.01)
        guard case .sharp(let high) = c5.verdict(heard: off(41)) else { return XCTFail("+41 cents is sharp") }
        XCTAssertEqual(high, 41, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(c5.cents(heard: off(-33))), -33, accuracy: 0.01)

        XCTAssertEqual(c5.verdict(heard: nil), .nothing)
        XCTAssertNil(c5.cents(heard: nil))
    }

    /// The miss a brass player makes that their fingers cannot explain: the
    /// right valves and the wrong partial. On a mellophone G4 and C5 are both
    /// open, so a student aiming at C5 who lands on G4 has to be told it is
    /// the air and not the valves. B4 is a different fingering, so there the
    /// valves ARE the thing to check.
    func testAWrongNoteIsNamedAsWrittenAndSaysWhetherTheValvesWereRight() throws {
        let c5 = try check("C5")
        func sounding(_ name: String) throws -> Double { try check(name).soundingFrequency }

        XCTAssertEqual(c5.verdict(heard: try sounding("G4")),
                       .wrongNote(writtenName: "G4", sameValves: true, tooHigh: false))
        XCTAssertEqual(c5.verdict(heard: try sounding("E5")),
                       .wrongNote(writtenName: "E5", sameValves: true, tooHigh: true))
        XCTAssertEqual(c5.verdict(heard: try sounding("B4")),
                       .wrongNote(writtenName: "B4", sameValves: false, tooHigh: false))

        // The same sound is a different written note on a trumpet, a fourth
        // lower: concert C4 is written G4 for an F horn and written D4 for Bb.
        XCTAssertEqual(try check("C5", on: .trumpet).writtenName(ofHeard: 261.63), "D4")
        XCTAssertEqual(try check("C5", on: .mellophone).writtenName(ofHeard: 261.63), "G4")
    }

    func testTheWordsMatchTheVerdict() throws {
        let c5 = try check("C5")
        XCTAssertEqual(c5.words(for: .nothing, confirmed: false).headline, "Play it and hold it")
        XCTAssertEqual(c5.words(for: .inTune(cents: 3), confirmed: false).headline, "That's C5")
        XCTAssertEqual(c5.words(for: .inTune(cents: 3), confirmed: true).headline, "That's it")
        XCTAssertEqual(c5.words(for: .inTune(cents: 3), confirmed: true).detail, "C5, Open")
        XCTAssertEqual(c5.words(for: .flat(cents: 32.6), confirmed: false).detail, "33 cents low")
        XCTAssertEqual(c5.words(for: .sharp(cents: 24.2), confirmed: false).detail, "24 cents high")
        XCTAssertEqual(c5.words(for: .wrongNote(writtenName: "G4", sameValves: true, tooHigh: false), confirmed: false).detail,
                       "Right valves, wrong note. Aim higher.")
        XCTAssertEqual(c5.words(for: .wrongNote(writtenName: "B4", sameValves: false, tooHigh: false), confirmed: false).detail,
                       "C5 is Open. Aim higher.")
    }

    // MARK: - Tuning the horn (#32)

    /// Published facts, not the app's numbers read back. A band tunes to
    /// concert F or concert Bb, and in equal temperament at A440 those are
    /// F3 174.61, Bb3 233.08, F4 349.23 and Bb4 466.16 Hz. Each horn's
    /// tuning notes have to SOUND one of them, and the first has to be the
    /// open note, because that is the one the main slide is set by.
    func testEachHornTunesToTheNotesABandCalls() throws {
        let expected: [Instrument: [(concert: String, written: String, hz: Double, fingering: String)]] = [
            .mellophone: [("F", "C5", 349.23, "Open"), ("Bb", "F4", 233.08, "1")],
            .frenchHorn: [("F", "C5", 349.23, "Open"), ("Bb", "F4", 233.08, "1")],
            .trumpet: [("Bb", "C5", 466.16, "Open"), ("F", "G4", 349.23, "Open")],
            .euphonium: [("Bb", "C5", 233.08, "Open"), ("F", "G4", 174.61, "Open")],
        ]
        XCTAssertEqual(Set(expected.keys), Set(Instrument.allCases), "a horn was added without tuning notes")
        for instrument in Instrument.allCases {
            let rows = try XCTUnwrap(expected[instrument])
            let targets = NoteCheckTarget.tuning(for: instrument)
            XCTAssertEqual(targets.count, rows.count, "\(instrument): a tuning note was dropped")
            for (target, row) in zip(targets, rows) {
                XCTAssertEqual(target.choice, "Concert \(row.concert)")
                XCTAssertEqual(target.check.writtenName, row.written, "\(instrument) concert \(row.concert)")
                XCTAssertEqual(target.check.soundingFrequency, row.hz, accuracy: 0.01, "\(instrument) concert \(row.concert)")
                XCTAssertTrue(target.check.soundingName.hasPrefix(row.concert), "\(target.check.soundingName) is not a concert \(row.concert)")
                XCTAssertEqual(target.fingering, row.fingering, "\(instrument) \(row.written)")
                XCTAssertEqual(target.drawn?.name, row.written)
                XCTAssertEqual(target.check.purpose, .tuning)
            }
            XCTAssertEqual(targets.first?.fingering, "Open", "\(instrument): the first tuning note is the one the main slide is set by")
        }
    }

    /// Fifteen cents out is the right note and a horn that needs its slide
    /// moved. The note check says yes to it and the tuner must not.
    func testTheTunerIsStricterThanTheNoteCheck() throws {
        let checking = try check("C5")
        var tuning = checking
        tuning.purpose = .tuning
        let target = checking.soundingFrequency
        func off(_ cents: Double) -> Double { target * pow(2, cents / 1200) }

        XCTAssertEqual(checking.tolerance, 20)
        XCTAssertEqual(tuning.tolerance, 10)
        for cents in [-9.9, -4, 0, 6, 9.9] {
            guard case .inTune = tuning.verdict(heard: off(cents)) else {
                XCTFail("\(cents) cents should be in tune on the tuner, got \(tuning.verdict(heard: off(cents)))"); continue
            }
        }
        guard case .inTune = checking.verdict(heard: off(15)) else { return XCTFail("the note check accepts 15 cents") }
        guard case .sharp(let high) = tuning.verdict(heard: off(15)) else { return XCTFail("the tuner must call 15 cents sharp") }
        XCTAssertEqual(high, 15, accuracy: 0.01)
        guard case .flat(let low) = tuning.verdict(heard: off(-12)) else { return XCTFail("the tuner must call -12 cents flat") }
        XCTAssertEqual(low, 12, accuracy: 0.01)
        // A wrong note is a wrong note on either screen.
        XCTAssertEqual(tuning.verdict(heard: try check("G4").soundingFrequency),
                       .wrongNote(writtenName: "G4", sameValves: true, tooHigh: false))
    }

    /// The line a tuner exists for: which way the slide goes. Sharp is a
    /// horn that is too short, so it comes OUT. Getting these two the wrong
    /// way round would send every student further from the note.
    func testTheTunerSaysWhichWayToMoveTheSlide() throws {
        var c5 = try check("C5")
        c5.purpose = .tuning
        XCTAssertEqual(c5.words(for: .sharp(cents: 14.4), confirmed: false).headline, "Sharp")
        XCTAssertEqual(c5.words(for: .sharp(cents: 14.4), confirmed: false).detail,
                       "14 cents high. Pull your tuning slide out a little.")
        XCTAssertEqual(c5.words(for: .flat(cents: 22.6), confirmed: false).headline, "Flat")
        XCTAssertEqual(c5.words(for: .flat(cents: 22.6), confirmed: false).detail,
                       "23 cents low. Push your tuning slide in a little.")
        XCTAssertEqual(c5.words(for: .inTune(cents: -3.2), confirmed: false).detail, "3 cents low. Hold it steady.")
        XCTAssertEqual(c5.words(for: .inTune(cents: 1.1), confirmed: true).detail, "1 cent high. Leave the slide there.")
        XCTAssertEqual(c5.words(for: .inTune(cents: 0.3), confirmed: true).headline, "In tune")
        XCTAssertEqual(c5.words(for: .inTune(cents: 0.3), confirmed: true).detail, "Dead on. Leave the slide there.")
        XCTAssertEqual(c5.words(for: .nothing, confirmed: false).headline, "Play it and hold it")
        // The wrong note is told the way the note check tells it.
        XCTAssertEqual(c5.words(for: .wrongNote(writtenName: "G4", sameValves: true, tooHigh: false), confirmed: false).detail,
                       "Right valves, wrong note. Aim higher.")
        // And the note check's own words did not change.
        XCTAssertEqual(try check("C5").words(for: .sharp(cents: 24.2), confirmed: false).detail, "24 cents high")
    }

    // MARK: - Holding it

    /// Sliding up through a pitch is not playing it.
    func testANoteHasToBeHeldToCountAndASlipTakesItBack() {
        var held = NoteConfirmation()
        for _ in 1..<NoteConfirmation.readingsNeeded {
            XCTAssertFalse(held.take(.inTune(cents: 2)))
        }
        XCTAssertFalse(held.isConfirmed, "one reading short")
        XCTAssertTrue(held.take(.inTune(cents: 2)), "this is the reading that confirms it")
        XCTAssertFalse(held.take(.inTune(cents: 2)), "and it says so once, not every reading after")
        XCTAssertTrue(held.isConfirmed)

        // A breath keeps the tick. A wrong sound is a new attempt.
        held.take(.nothing)
        XCTAssertTrue(held.isConfirmed)
        held.take(.flat(cents: 30))
        XCTAssertFalse(held.isConfirmed)

        // One short of enough, a wobble, one short again: never enough in a
        // row.
        var wobbly = NoteConfirmation()
        for _ in 1..<NoteConfirmation.readingsNeeded { wobbly.take(.inTune(cents: 0)) }
        wobbly.take(.sharp(cents: 25))
        for _ in 1..<NoteConfirmation.readingsNeeded { wobbly.take(.inTune(cents: 0)) }
        XCTAssertFalse(wobbly.isConfirmed)
    }

    /// The listener holds a sound back for two readings and the screen then
    /// counts its own. A student is asked for six tenths of a second in all,
    /// which is what they were asked for before either count existed apart.
    func testANoteIsStillConfirmedSixReadingsAfterItStarts() {
        var held = HeldPitch()
        var confirmation = NoteConfirmation()
        let check = NoteCheck(writtenName: "C5", writtenFrequency: 523.25, instrument: .trumpet, purpose: .tuning)
        var confirmedAt: Int?
        for reading in 1...10 {
            let shown = held.take(frequency: check.soundingFrequency, level: 0.15)
            if confirmation.take(check.verdict(heard: shown)) { confirmedAt = reading }
        }
        XCTAssertEqual(confirmedAt, 6)
    }
}

/// Which sounds the listener passes on at all (#34).
///
/// What is and is not real here, said once: the first four tests run on
/// numbers typed into them. The levels in the struck sound test were READ OFF
/// a real one (macOS Glass, through the scratch harness) and then typed. The
/// last test is the only one that reads real audio, the alert sounds on the
/// Mac the simulator runs on, and it reads them from their files: none of
/// this has been through a speaker, a room and a phone's microphone, and no
/// test here has heard a horn.
final class HeldPitchTests: XCTestCase {

    private func feed(_ held: inout HeldPitch, _ readings: [(Double?, Double)]) -> [Double?] {
        readings.map { held.take(frequency: $0.0, level: $0.1) }
    }

    func testASoundIsNotShownUntilItHasHeldOneNote() {
        var held = HeldPitch()
        XCTAssertNil(held.take(frequency: 349.2, level: 0.15))
        XCTAssertNil(held.take(frequency: 349.6, level: 0.16))
        XCTAssertEqual(held.outcome, .waiting)
        XCTAssertEqual(held.take(frequency: 348.9, level: 0.15) ?? 0, 349.2, accuracy: 0.01, "the third reading shows the middle of the three")
        XCTAssertEqual(held.outcome, .held)

        // Silence ends it, and the next note starts from nothing.
        XCTAssertNil(held.take(frequency: nil, level: 0.001))
        XCTAssertEqual(held.outcome, .silence)
        XCTAssertNil(held.take(frequency: 349.2, level: 0.15))

        // Two readings on one note and a third a tone away: a sound that
        // moves is not a note being held. Speech and jingles do this.
        var moving = HeldPitch()
        let shown = feed(&moving, [(440, 0.1), (441, 0.1), (494, 0.1), (495, 0.1), (554, 0.1), (556, 0.1)])
        XCTAssertTrue(shown.allSatisfy { $0 == nil }, "a tune in two reading steps was shown: \(shown)")
    }

    /// The bug as reported: a new mail chime read as a note. A chime is
    /// steadier in pitch than a student. What gives it away is that it was
    /// struck, and is dying from its first reading.
    func testAStruckSoundThatDiesAwayIsNeverShownHoweverSteadyItsPitch() {
        // macOS Glass at full level: 391 to 393 Hz for six readings running.
        let glass: [(Double?, Double)] = [(393, 0.062), (391, 0.090), (392, 0.031), (392, 0.015), (391, 0.011), (nil, 0.005)]
        for scale in [1.0, 0.5, 0.25] {
            var held = HeldPitch()
            let shown = feed(&held, glass.map { ($0.0, $0.1 * scale) })
            XCTAssertTrue(shown.allSatisfy { $0 == nil }, "at \(scale) of its level the chime was shown: \(shown)")
        }

        // The control: the same six pitches at a level that does not fall
        // ARE a note, so it is the dying that is being caught and nothing
        // else about these numbers.
        var blown = HeldPitch()
        let shown = feed(&blown, glass.dropLast().map { ($0.0, 0.09) })
        XCTAssertEqual(shown.compactMap { $0 }.count, 3)
    }

    /// One block in a held note now and then comes back an octave out. That
    /// must not blank the screen, and two in a row must not be ignored.
    func testOneStrayReadingKeepsAHeldNoteAndTwoAreANewNote() {
        var held = HeldPitch()
        _ = feed(&held, [(349, 0.15), (349, 0.15), (349, 0.15)])
        XCTAssertEqual(held.take(frequency: 698, level: 0.15), 349, "the octave error is thrown away and the note stays")
        XCTAssertEqual(held.take(frequency: 350, level: 0.15) ?? 0, 349, accuracy: 0.01)

        // Up to the next partial and staying there.
        XCTAssertEqual(held.take(frequency: 466, level: 0.15), 349, "one reading elsewhere is still the stray")
        XCTAssertNil(held.take(frequency: 467, level: 0.15), "two is a move, and the new note has not held yet")
        XCTAssertEqual(held.outcome, .moved)
        XCTAssertEqual(held.take(frequency: 466, level: 0.15) ?? 0, 466, accuracy: 0.01, "the two that moved count toward the new note")
    }

    /// The other half of the dying rule: it must not drop a horn. A held note
    /// that wanders 20 cents either way and swells and sags by a quarter,
    /// which is more than the trumpet in the session behind #34 did from one
    /// second to the next, stays held from its third reading to its last.
    ///
    /// Made here. It says the arithmetic leaves that much room, not that a
    /// student's note fits in it.
    func testAHeldNoteThatWandersAndSwellsStaysHeld() {
        var held = HeldPitch()
        var shown = 0
        for reading in 0..<40 {
            let cents = 20 * sin(Double(reading) * 0.9)
            let level = 0.15 * (1 + 0.25 * sin(Double(reading) * 1.7))
            if held.take(frequency: 349.23 * pow(2, cents / 1200), level: level) != nil { shown += 1 }
        }
        XCTAssertEqual(shown, 40 - (HeldPitch.readingsNeeded - 1))

        // And a note let go: the tail is dropped, which is right, the tail of
        // a brass note sags in pitch as it goes.
        XCTAssertNil(held.take(frequency: 345, level: 0.04))
        XCTAssertEqual(held.outcome, .died)
    }

    /// Real alert sounds, through the real detector and the real gate, in the
    /// blocks a phone hands over and at four places the sound could land in
    /// them.
    ///
    /// The sounds are the ones macOS ships and are read off the Mac running
    /// the simulator; nothing of Apple's is in this repo. Skipped, loudly,
    /// where they are not there to read.
    func testNoMacAlertSoundCanBeTakenForANote() throws {
        let folders = ["/System/Library/Sounds", "/System/Applications/Mail.app/Contents/Resources"]
        let files = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                .filter { $0.hasSuffix(".aiff") || $0.hasSuffix(".wav") }
                .map { "\(folder)/\($0)" }
        }.sorted()
        try XCTSkipIf(files.count < 10, "[LISTEN] only \(files.count) alert sounds could be read from this machine, the real sound test did not run")

        var pitchedBefore = 0, shownAfter = 0, runs = 0
        var longestBefore = 0
        for path in files {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let data = try XCTUnwrap(buffer.floatChannelData)[0]
            let sound = (0..<Int(buffer.frameLength)).map { Double(data[$0]) }
            let rate = file.processingFormat.sampleRate
            let block = Int(rate / 10)

            for alignment in 0..<4 {
                let samples = [Double](repeating: 0, count: alignment * block / 4) + sound
                var ring: [Double] = []
                var held = HeldPitch()
                var shown = 0, pitched = 0, streak = 0
                var from = 0
                while from < samples.count {
                    ring.append(contentsOf: samples[from..<min(from + block, samples.count)])
                    from += block
                    if ring.count > PitchListener.scopeWindow { ring.removeFirst(ring.count - PitchListener.scopeWindow) }
                    guard ring.count >= PitchListener.window else { continue }
                    let frame = PitchAnalysis.frame(of: Array(ring.suffix(PitchListener.window)), sampleRate: rate)
                    if frame.frequency != nil {
                        pitched += 1
                        streak += 1
                        longestBefore = max(longestBefore, streak)
                    } else {
                        streak = 0
                    }
                    if held.take(frequency: frame.frequency, level: frame.level) != nil { shown += 1 }
                }
                runs += 1
                if pitched > 0 { pitchedBefore += 1 }
                if shown > 0 { shownAfter += 1 }
                // Fewer readings than the screen needs to call a note played,
                // so whatever a chime does to the needle, it cannot be
                // counted as the student's note.
                XCTAssertLessThan(shown, NoteConfirmation.readingsNeeded,
                                  "\((path as NSString).lastPathComponent) at alignment \(alignment) was shown for \(shown) readings")
            }
        }
        print("[LISTEN] \(files.count) alert sounds, \(runs) runs: the detector gives \(pitchedBefore) of them a pitch, \(shownAfter) reach the screen, longest pitched streak \(longestBefore)")

        // The control. If the detector gave none of these a pitch there
        // would be nothing for the gate to do and this test would prove
        // nothing: most of them have one, and at least one holds it for
        // longer than a confirmation takes.
        XCTAssertGreaterThan(pitchedBefore, runs / 2)
        XCTAssertGreaterThanOrEqual(longestBefore, NoteConfirmation.readingsNeeded)
        XCTAssertLessThan(shownAfter, runs / 10)
    }
}

/// The half that listens: is this block of audio a note, which one, and what
/// does it look like.
final class PitchAnalysisTests: XCTestCase {

    private let rate = 48_000.0

    private var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)! }

    /// One listener's worth of samples out of the steady middle of a note the
    /// app's own renderer made.
    private func window(of frequency: Double, volume: Double = 0.4, count: Int = PitchListener.window) throws -> [Double] {
        let buffer = try XCTUnwrap(TonePlayer.render(frequency: frequency, duration: 0.6, volume: volume, format: format))
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        let from = Int(0.25 * rate)
        return (from..<(from + count)).map { Double(data[$0]) }
    }

    /// A plain harmonic tone made here: twelve overtones falling off as a
    /// sawtooth's do. NOT the app's tone, on purpose. The app's is filtered
    /// at one and a half times its own pitch, so a low one has next to
    /// nothing over 300 Hz, and that is a fact about this app's synthesiser
    /// and not about a euphonium, whose low notes are mostly overtone.
    private func harmonicTone(_ frequency: Double, seconds: Double = 0.6, sampleRate: Double? = nil) -> [Double] {
        let rate = sampleRate ?? self.rate
        return (0..<Int(seconds * rate)).map { n in
            var sample = 0.0
            for h in 1...12 { sample += sin(2 * Double.pi * frequency * Double(h) * Double(n) / rate) / Double(h) }
            return sample * 0.2
        }
    }

    /// What a small transducer does to a low note, a phone's microphone or
    /// its speaker: everything under `cut` is taken away, 24 dB an octave.
    /// A guess at a phone, not a measurement of one.
    private func highPassed(_ samples: [Double], cut: Double = 300, sampleRate: Double? = nil) -> [Double] {
        let rate = sampleRate ?? self.rate
        var x = samples
        for _ in 0..<2 {
            // A second order Butterworth high pass, twice.
            let w = 2 * Double.pi * cut / rate, alpha = sin(w) / (2 * 0.7071), c = cos(w)
            let b0 = (1 + c) / 2, b1 = -(1 + c), b2 = (1 + c) / 2, a0 = 1 + alpha, a1 = -2 * c, a2 = 1 - alpha
            var y = [Double](repeating: 0, count: x.count)
            for n in 2..<x.count {
                y[n] = (b0 * x[n] + b1 * x[n - 1] + b2 * x[n - 2] - a1 * y[n - 1] - a2 * y[n - 2]) / a0
            }
            x = y
        }
        return x
    }

    /// One listener's worth from a quarter of a second in, by which time the
    /// filter above has settled.
    private func steadyWindow(_ samples: [Double]) -> [Double] {
        let from = Int(0.25 * rate)
        return Array(samples[from..<(from + PitchListener.window)])
    }

    private func rms(_ samples: [Double]) -> Double {
        (samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)).squareRoot()
    }

    /// How much of `window` is a sine at `frequency`, as an amplitude.
    private func amount(of frequency: Double, in window: [Double]) -> Double {
        var re = 0.0, im = 0.0
        for (n, value) in window.enumerated() {
            re += value * cos(2 * Double.pi * frequency * Double(n) / rate)
            im += value * sin(2 * Double.pi * frequency * Double(n) / rate)
        }
        return 2 * (re * re + im * im).squareRoot() / Double(window.count)
    }

    private func sine(_ frequency: Double, phase: Double = 0, count: Int = PitchListener.window) -> [Double] {
        (0..<count).map { sin(2 * Double.pi * frequency * Double($0) / rate + phase) * 0.3 }
    }

    // MARK: - Calibrate, again, where the app had never looked

    /// The detector was calibrated from 147 Hz up, because that is as low as
    /// the app's own audio goes. A mellophone's bottom note SOUNDS 123 Hz and
    /// a wrong partial under it is lower still, so the listening range starts
    /// at 70 Hz and has to be shown to work there before it judges a student.
    /// Signals of known pitch, built here and not by the app.
    func testTheDetectorIsAccurateBelowWhereTheAppItselfPlays() {
        for frequency in [77.78, 87.31, 98.0, 110.0, 123.47, 138.59] {
            for harmonics in [1, 8, 24] {
                var samples = [Double](repeating: 0, count: PitchListener.window)
                for i in 0..<samples.count {
                    for h in 1...harmonics {
                        samples[i] += sin(2 * Double.pi * Double(h) * frequency * Double(i) / rate) / Double(h) * 0.2
                    }
                }
                let frame = PitchAnalysis.frame(of: samples, sampleRate: rate)
                guard let heard = frame.frequency else {
                    XCTFail("no pitch found for \(frequency) Hz with \(harmonics) harmonics"); continue
                }
                XCTAssertEqual(Pitch.cents(heard, frequency), 0, accuracy: 5,
                               "\(harmonics) harmonics at \(frequency) Hz: heard \(heard) Hz")
            }
        }
    }

    // MARK: - Calibrate, again, for a tuner (#32)

    /// A note a few cents out, at every pitch a horn is tuned to.
    ///
    /// The note check only ever asked the detector for "within 20 cents". A
    /// tuner's band is 10 and the number on the screen is read to the cent,
    /// so the detector has to be shown good for that before it is used for
    /// it: every fifth cent from 40 flat to 40 sharp, at 44.1 and 48 kHz,
    /// clean and with everything under 300 Hz taken out the way a phone's
    /// microphone takes it. The reading has to be within half a cent and the
    /// verdict has to be the right one.
    ///
    /// The eight tuning notes are four sounds (a mellophone's concert F is a
    /// trumpet's), so four are measured. That and the five cent step are for
    /// time: the detector is slow in a debug build and this is 272 tones.
    /// Every single cent, with noise, was measured once outside the suite and
    /// is written up in `ios/README.md`.
    ///
    /// What this does not show. The tone is twelve steady overtones made in
    /// this file. A student's note wavers, starts with a splat and has a room
    /// round it, and no horn has been played at this screen.
    func testANoteAFewCentsOutIsReadToHalfACentAtEveryTuningPitch() throws {
        var checks: [NoteCheck] = []
        for target in Instrument.allCases.flatMap(NoteCheckTarget.tuning) {
            if !checks.contains(where: { abs($0.soundingFrequency - target.check.soundingFrequency) < 0.01 }) {
                checks.append(target.check)
            }
        }
        XCTAssertEqual(checks.map { $0.soundingFrequency.rounded() }.sorted(), [175, 233, 349, 466])

        var worst = 0.0, readings = 0
        for check in checks {
            for sampleRate in [44_100.0, 48_000.0] {
                for filtered in [false, true] {
                    for offset in stride(from: -40.0, through: 40.0, by: 5.0) {
                        let played = check.soundingFrequency * pow(2, offset / 1200)
                        // A tenth of a second of run-in for the filter to
                        // settle in, and none where there is no filter.
                        let from = filtered ? Int(0.1 * sampleRate) : 0
                        let seconds = Double(from + PitchListener.window + 1) / sampleRate
                        var samples = harmonicTone(played, seconds: seconds, sampleRate: sampleRate)
                        if filtered { samples = highPassed(samples, sampleRate: sampleRate) }
                        let window = Array(samples[from..<(from + PitchListener.window)])
                        let label = String(format: "%.2f Hz %+.0f cents at %.0f Hz%@", check.soundingFrequency, offset,
                                           sampleRate, filtered ? ", nothing under 300 Hz" : "")
                        guard let heard = PitchAnalysis.frame(of: window, sampleRate: sampleRate).frequency else {
                            XCTFail("no pitch: \(label)"); continue
                        }
                        let error = abs(Pitch.cents(heard, played))
                        worst = max(worst, error)
                        readings += 1
                        XCTAssertLessThan(error, 0.5, label)

                        // On the line itself either answer is right.
                        guard abs(abs(offset) - check.tolerance) > 0.5 else { continue }
                        switch check.verdict(heard: heard) {
                        case .inTune: XCTAssertLessThan(abs(offset), check.tolerance, label)
                        case .sharp: XCTAssertGreaterThan(offset, check.tolerance, label)
                        case .flat: XCTAssertLessThan(offset, -check.tolerance, label)
                        default: XCTFail("\(label): \(check.verdict(heard: heard))")
                        }
                    }
                }
            }
        }
        // 4 pitches x 2 rates x 2 filters x 17 offsets.
        XCTAssertEqual(readings, 272)
        print(String(format: "[TUNE] %d readings, worst %.3f cents", readings, worst))
    }

    // MARK: - End to end, short of the microphone

    /// Every note in the table, on every instrument: the app's own tone at the
    /// pitch THAT INSTRUMENT sounds, through one listener window, the shipping
    /// detector and the verdict. Each has to come back in tune.
    ///
    /// The tone is the app's sawtooth and not a horn. It is harmonically
    /// rich in the same way, which is the property that breaks detectors, but
    /// it is steady and clean and a student is neither.
    func testEveryNoteAtItsSoundingPitchIsHeardAsInTune() throws {
        var worst = 0.0
        for instrument in Instrument.allCases {
            for note in Note.all {
                let check = NoteCheck(writtenName: note.name, writtenFrequency: note.frequency, instrument: instrument)
                let frame = PitchAnalysis.frame(of: try window(of: check.soundingFrequency), sampleRate: rate)
                let heard = try XCTUnwrap(frame.frequency, "\(note.name) on \(instrument.shortName): nothing heard")
                worst = max(worst, abs(Pitch.cents(heard, check.soundingFrequency)))
                guard case .inTune = check.verdict(heard: heard) else {
                    XCTFail("\(note.name) on \(instrument.shortName) at \(check.soundingFrequency) Hz: heard \(heard), judged \(check.verdict(heard: heard))")
                    continue
                }
            }
        }
        print("NOTE CHECK worst error over the whole table:", worst, "cents")
        XCTAssertLessThan(worst, 5)
    }

    /// A euphonium's low notes, heard the way a phone hears them (#25).
    ///
    /// The bottom of that horn sounds 82 Hz and a phone's microphone has
    /// very little to say about anything that low. So the fundamental the
    /// detector is asked to name may, on a phone, not be in the signal at
    /// all. This takes it out, proves it is out, and asks anyway.
    ///
    /// What this does and does not show. It shows the DETECTOR does not need
    /// the fundamental. It does not show a real euphonium through a real
    /// phone is loud enough to be looked at: the tone is made in this file
    /// and the filter is a guess. No euphonium has been played at this app.
    func testAEuphoniumIsHeardThroughAMicrophoneThatCannotHearItsFundamental() throws {
        var worst = 0.0
        for note in Note.all {
            let check = NoteCheck(writtenName: note.name, writtenFrequency: note.frequency, instrument: .euphonium)
            let whole = harmonicTone(check.soundingFrequency)
            let filtered = steadyWindow(highPassed(whole))
            if check.soundingFrequency < 150 {
                let before = amount(of: check.soundingFrequency, in: steadyWindow(whole))
                let after = amount(of: check.soundingFrequency, in: filtered)
                XCTAssertLessThan(after, before / 10, "\(note.name): the filter left the fundamental in, so this proves nothing")
            }
            let frame = PitchAnalysis.frame(of: filtered, sampleRate: rate)
            let heard = try XCTUnwrap(frame.frequency, "\(note.name) at \(check.soundingFrequency) Hz: nothing heard, level \(frame.level)")
            worst = max(worst, abs(Pitch.cents(heard, check.soundingFrequency)))
            guard case .inTune = check.verdict(heard: heard) else {
                XCTFail("\(note.name) at \(check.soundingFrequency) Hz: heard \(heard), judged \(check.verdict(heard: heard))")
                continue
            }
        }
        print("NOTE CHECK euphonium with no fundamental, worst error:", worst, "cents")
        XCTAssertLessThan(worst, 5)
    }

    /// Under the bottom of the horn. A student reaching for the low written
    /// F# who gets the pedal instead is playing concert Bb1, 58 Hz, and has
    /// to be TOLD that, not shown an empty screen. The detector's floor was
    /// 70 Hz before the euphonium and this note was under it.
    func testTheEuphoniumsPedalNoteIsNamed() throws {
        let check = NoteCheck(writtenName: "F#3", writtenFrequency: try XCTUnwrap(Note.named("F#3")).frequency,
                              instrument: .euphonium)
        let pedal = 58.27
        let whole = harmonicTone(pedal)
        for (what, window) in [("whole", steadyWindow(whole)), ("with no fundamental", steadyWindow(highPassed(whole)))] {
            let frame = PitchAnalysis.frame(of: window, sampleRate: rate)
            let heard = try XCTUnwrap(frame.frequency, "the pedal, \(what), was not heard at level \(frame.level)")
            XCTAssertEqual(Pitch.cents(heard, pedal), 0, accuracy: 5, what)
            XCTAssertEqual(check.verdict(heard: heard), .wrongNote(writtenName: "C3", sameValves: false, tooHigh: false), what)
        }
    }

    // MARK: - What the phone can play back

    /// "Hear it" out of a phone's speaker, for every note on every horn (#25).
    ///
    /// The reference tone is the SOUNDING pitch, and a phone's speaker makes
    /// very little under about 300 Hz. This measures how much of each
    /// reference note is left above that, against the best case on the same
    /// horn, first as the app's ordinary tone and then with the filter held
    /// open the way the note check holds it.
    ///
    /// Without the floor a euphonium's low E keeps a few hundredths of what
    /// its high notes do, which on a speaker is a note nobody hears. With it,
    /// the quietest note on any horn has to stay within 12 dB of the loudest.
    ///
    /// The 300 Hz corner is an assumption about a phone and the measure is
    /// energy, not loudness. It says the sound is THERE to be played. Whether
    /// it reads as a low E to a student's ear has to be listened to.
    func testTheReferenceToneSurvivesASmallSpeakerOnEveryHorn() throws {
        func left(_ frequency: Double, floor: Double) throws -> Double {
            let buffer = try XCTUnwrap(TonePlayer.render(frequency: frequency, duration: 0.6, volume: 0.4,
                                                         format: format, brightnessFloor: floor))
            let data = try XCTUnwrap(buffer.floatChannelData)[0]
            return rms(steadyWindow(highPassed((0..<Int(buffer.frameLength)).map { Double(data[$0]) })))
        }
        for instrument in Instrument.allCases {
            var plain: [Double] = [], held: [Double] = []
            for note in Note.all {
                let check = NoteCheck(writtenName: note.name, writtenFrequency: note.frequency, instrument: instrument)
                plain.append(try left(check.soundingFrequency, floor: 0))
                held.append(try left(check.soundingFrequency, floor: NoteCheck.referenceBrightnessFloor))
            }
            func spread(_ levels: [Double]) -> Double { 20 * log10(levels.max()! / levels.min()!) }
            print(String(format: "SPEAKER %@: quietest note is %.1f dB under the loudest as the plain tone, %.1f dB with the filter held open",
                         instrument.shortName, spread(plain), spread(held)))
            XCTAssertLessThan(spread(held), 12, "\(instrument.shortName): a reference note is lost on a small speaker")
            if instrument == .euphonium {
                // The reason the floor exists. If this ever stops being true
                // the floor is doing nothing and can go.
                XCTAssertGreaterThan(spread(plain), 20, "the plain tone was fine after all")
            }
        }
    }

    /// The floor must not touch a note the app was already playing: with no
    /// floor asked for, `render` returns the samples it always has, and a
    /// note whose filter already sits above the floor is not changed by it.
    func testTheBrightnessFloorChangesNothingItShouldNot() throws {
        func samples(_ frequency: Double, floor: Double?) throws -> [Float] {
            let buffer = try XCTUnwrap(floor.map {
                TonePlayer.render(frequency: frequency, duration: 0.3, volume: 0.4, format: format, brightnessFloor: $0)
            } ?? TonePlayer.render(frequency: frequency, duration: 0.3, volume: 0.4, format: format))
            return Array(UnsafeBufferPointer(start: try XCTUnwrap(buffer.floatChannelData)[0], count: Int(buffer.frameLength)))
        }
        XCTAssertEqual(try samples(82.41, floor: 0), try samples(82.41, floor: nil))
        // 523 Hz closes to 785, which is over the floor already.
        XCTAssertEqual(try samples(523.25, floor: NoteCheck.referenceBrightnessFloor), try samples(523.25, floor: nil))
        XCTAssertNotEqual(try samples(82.41, floor: NoteCheck.referenceBrightnessFloor), try samples(82.41, floor: nil))
    }

    /// And the pitch of the brighter tone is still the pitch: the reference
    /// is the thing a student tunes to.
    func testTheBrighterReferenceToneIsStillOnPitch() throws {
        for instrument in Instrument.allCases {
            for note in Note.all {
                let check = NoteCheck(writtenName: note.name, writtenFrequency: note.frequency, instrument: instrument)
                let buffer = try XCTUnwrap(TonePlayer.render(frequency: check.soundingFrequency, duration: 0.6, volume: 0.4,
                                                             format: format, brightnessFloor: NoteCheck.referenceBrightnessFloor))
                let data = try XCTUnwrap(buffer.floatChannelData)[0]
                let window = steadyWindow((0..<Int(buffer.frameLength)).map { Double(data[$0]) })
                let heard = try XCTUnwrap(PitchAnalysis.frame(of: window, sampleRate: rate).frequency, "\(note.name) on \(instrument.shortName)")
                XCTAssertEqual(Pitch.cents(heard, check.soundingFrequency), 0, accuracy: 2, "\(note.name) on \(instrument.shortName)")
            }
        }
    }

    /// The control. A semitone out has to be CAUGHT, for every note, or the
    /// test above would pass on a detector that says yes to anything.
    func testASemitoneOutIsCaughtForEveryNote() throws {
        for note in Note.all {
            let check = NoteCheck(writtenName: note.name, writtenFrequency: note.frequency, instrument: .mellophone)
            let frame = PitchAnalysis.frame(of: try window(of: check.soundingFrequency * pow(2, 1.0 / 12)),
                                            sampleRate: rate)
            guard case .wrongNote(_, _, let tooHigh) = check.verdict(heard: frame.frequency) else {
                XCTFail("\(note.name): a semitone sharp was judged \(check.verdict(heard: frame.frequency))"); continue
            }
            XCTAssertTrue(tooHigh)
        }
    }

    /// A quiet room, a loud room that is not a note, and a note too far away
    /// to trust. None of them is a pitch.
    func testSilenceAndNoiseAreNotNotes() throws {
        XCTAssertNil(PitchAnalysis.frame(of: [Double](repeating: 0, count: PitchListener.window), sampleRate: rate).frequency)

        // A fixed seed, so a failure here is the same failure tomorrow.
        var generator = SystemRandomNumberGenerator()
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 2 - 1
        }
        _ = generator.next()
        for trial in 0..<20 {
            let noise = (0..<PitchListener.window).map { _ in next() * 0.2 }
            let frame = PitchAnalysis.frame(of: noise, sampleRate: rate)
            XCTAssertGreaterThan(frame.level, PitchAnalysis.quietest, "the noise has to be loud enough to be looked at")
            XCTAssertNil(frame.frequency, "trial \(trial): white noise was given a pitch of \(frame.frequency ?? 0) Hz")
        }

        let faint = try window(of: 349.23, volume: 0.4).map { $0 * 0.005 }
        let frame = PitchAnalysis.frame(of: faint, sampleRate: rate)
        XCTAssertLessThan(frame.level, PitchAnalysis.quietest)
        XCTAssertNil(frame.frequency)
    }

    // MARK: - The picture

    /// The scope starts where the fundamental goes up through zero. For a
    /// sine whose phase is chosen here, that sample is known exactly.
    func testTheScopeStartsWhereTheWaveGoesUpThroughZero() {
        let frequency = 349.23
        let period = rate / frequency
        for phase in [0.0, 0.7, 2.0, 3.1, 4.4, 5.9] {
            let start = PitchAnalysis.risingCrossing(of: sine(frequency, phase: phase), sampleRate: rate, frequency: frequency)
            // sin(w n + phase) goes up through zero where w n + phase is a
            // multiple of 2 pi.
            var expected = (-phase / (2 * Double.pi) * period).truncatingRemainder(dividingBy: period)
            if expected < 0 { expected += period }
            let difference = abs(start - expected)
            XCTAssertLessThan(min(difference, period - difference), 0.5, "phase \(phase): started at \(start), should be \(expected)")
        }
    }

    /// On pitch, the trace of a sine IS the target the screen draws behind it.
    func testOnPitchTheWaveLiesOnTheTarget() {
        let frequency = 277.18
        let trace = PitchAnalysis.trace(of: sine(frequency, phase: 1.3), sampleRate: rate, heard: frequency, target: frequency)
        XCTAssertEqual(trace.count, 240)
        var worst = 0.0
        for (i, value) in trace.enumerated() {
            let target = sin(2 * Double.pi * Double(PitchAnalysis.traceCycles) * Double(i) / Double(trace.count - 1))
            worst = max(worst, abs(Double(value) - target))
        }
        XCTAssertLessThan(worst, 0.05, "the wave is off the target by \(worst) of full height")
    }

    /// The same, for a sound that is nothing like a sine: the app's own
    /// sawtooth, which is mostly overtones, the way a horn is. Drawn raw it is
    /// a scribble over the target. Smoothed, it has to lie close enough to the
    /// gold line to be read as "on it".
    func testABrassyToneOnPitchStillLiesOnTheTarget() throws {
        for frequency in [123.47, 277.18, 349.23, 698.46] {
            let trace = PitchAnalysis.trace(of: try window(of: frequency), sampleRate: rate, heard: frequency, target: frequency)
            XCTAssertEqual(trace.count, 240, "\(frequency) Hz gave no picture")
            var worst = 0.0
            for (i, value) in trace.enumerated() {
                let target = sin(2 * Double.pi * Double(PitchAnalysis.traceCycles) * Double(i) / Double(trace.count - 1))
                worst = max(worst, abs(Double(value) - target))
            }
            print("SCOPE", frequency, "Hz, furthest from the target:", worst)
            XCTAssertLessThan(worst, 0.2, "\(frequency) Hz: the wave is off the target by \(worst) of full height")
        }
    }

    /// The bottom of a euphonium (#25). Six cycles of its low E do not fit in
    /// the stretch the pitch is measured on, which is why the listener keeps
    /// twice that for the picture. Both halves are checked: one window draws
    /// nothing, and the listener's longer one draws the note on its target.
    func testTheScopeDrawsAEuphoniumsLowestNote() throws {
        let lowE = 82.41
        XCTAssertTrue(PitchAnalysis.trace(of: try window(of: lowE), sampleRate: rate, heard: lowE, target: lowE).isEmpty,
                      "one measurement window was enough after all, and the longer one is not needed")
        for frequency in [lowE, 87.31, 92.50, 233.08] {
            let long = try window(of: frequency, count: PitchListener.scopeWindow)
            let trace = PitchAnalysis.trace(of: long, sampleRate: rate, heard: frequency, target: frequency)
            XCTAssertEqual(trace.count, 240, "\(frequency) Hz gave no picture")
            var worst = 0.0
            for (i, value) in trace.enumerated() {
                let target = sin(2 * Double.pi * Double(PitchAnalysis.traceCycles) * Double(i) / Double(trace.count - 1))
                worst = max(worst, abs(Double(value) - target))
            }
            print("SCOPE", frequency, "Hz in the long window, furthest from the target:", worst)
            XCTAssertLessThan(worst, 0.2, "\(frequency) Hz: the wave is off the target by \(worst) of full height")
        }
        // The worst case for room: the lowest thing the detector will name,
        // heard while the lowest note there is was wanted.
        let pedal = try window(of: PitchAnalysis.lowestHz + 2, count: PitchListener.scopeWindow)
        XCTAssertEqual(PitchAnalysis.trace(of: pedal, sampleRate: rate, heard: PitchAnalysis.lowestHz + 2, target: lowE).count, 240)
    }

    /// Flat, the wave falls behind the target, more the further right it
    /// goes, by an amount that is arithmetic: 50 cents flat is 2.93% longer
    /// per cycle, so the wave's last upward crossing in six target cycles
    /// comes that much later for each of the cycles before it. Sharp, earlier.
    func testFlatFallsBehindTheTargetAndSharpRunsAhead() {
        let target = 277.18
        func upwardCrossings(_ trace: [Float]) -> [Double] {
            var found: [Double] = []
            for i in 1..<trace.count where trace[i - 1] < 0 && trace[i] >= 0 {
                let fraction = Double(-trace[i - 1]) / Double(trace[i] - trace[i - 1])
                // In target cycles from the left edge.
                found.append((Double(i - 1) + fraction) / Double(trace.count - 1) * Double(PitchAnalysis.traceCycles))
            }
            return found
        }
        let flat = target * pow(2, -50.0 / 1200)
        let flatCrossings = upwardCrossings(PitchAnalysis.trace(of: sine(flat, phase: 0.4), sampleRate: rate, heard: flat, target: target))
        // The fifth cycle of the heard wave starts 5 x (target / heard) target
        // cycles in.
        XCTAssertEqual(try XCTUnwrap(flatCrossings.last), 5 * target / flat, accuracy: 0.03)
        XCTAssertGreaterThan(try XCTUnwrap(flatCrossings.last), 5.1, "50 cents flat has to be visibly behind")

        let sharp = target * pow(2, 50.0 / 1200)
        let sharpCrossings = upwardCrossings(PitchAnalysis.trace(of: sine(sharp, phase: 0.4), sampleRate: rate, heard: sharp, target: target))
        XCTAssertEqual(try XCTUnwrap(sharpCrossings.first { $0 > 4.5 }), 5 * target / sharp, accuracy: 0.03)
    }
}

/// The audio session's second mode, on the simulator's real session.
///
/// What this cannot see: a microphone, the orange dot, the earpiece. Whether
/// the reference tone comes out of the speaker with the session set to record
/// is a question only a phone answers.
final class ListeningSessionTests: XCTestCase {

    override func tearDown() {
        AudioSessionController.shared.endListening()
        UserDefaults.standard.removeObject(forKey: "listenFake")
        super.tearDown()
    }

    func testListeningIsEnteredAndLeftAndPlaybackComesBackExactlyAsItWas() {
        let session = AVAudioSession.sharedInstance()
        XCTAssertTrue(AudioSessionController.shared.activate())
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.categoryOptions, [], "requirement 3: no options on the playback category")

        XCTAssertTrue(AudioSessionController.shared.beginListening())
        XCTAssertEqual(AudioSessionController.shared.mode, .listening)
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertTrue(session.categoryOptions.contains(.defaultToSpeaker), "without it the reference tone plays in the earpiece")
        XCTAssertFalse(session.categoryOptions.contains(.mixWithOthers))

        // A player making a sound while the check screen is up calls this. It
        // must not put the session back and turn the microphone off.
        XCTAssertTrue(AudioSessionController.shared.activate())
        XCTAssertEqual(session.category, .playAndRecord)

        AudioSessionController.shared.endListening()
        XCTAssertEqual(AudioSessionController.shared.mode, .playback)
        XCTAssertEqual(session.category, .playback)
        XCTAssertEqual(session.categoryOptions, [])
    }

    /// The listener, with the debug stand-in for the microphone in place of a
    /// real one. Everything after the microphone is the shipping code: the
    /// blocks, the ring, the detector, the hold, the publish.
    ///
    /// NOT a microphone test. The stand-in is a steady synthetic tone.
    func testTheListenerNamesASteadyToneAndGoesDeafWhileTheAppPlays() {
        UserDefaults.standard.set(349.23, forKey: "listenFake")
        let listener = PitchListener()
        listener.start(target: 349.23)
        XCTAssertEqual(listener.state, .listening)

        let heardIt = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in listener.reading.frequency != nil }, object: nil)
        wait(for: [heardIt], timeout: 5)
        XCTAssertEqual(Pitch.cents(listener.reading.frequency ?? 1, 349.23), 0, accuracy: 5)
        XCTAssertFalse(listener.reading.trace.isEmpty, "a note that was heard has a wave to draw")

        // Two readings of the same steady note still have to differ, or the
        // screen never counts the note as held.
        let first = listener.reading
        let another = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in listener.reading.sequence > first.sequence }, object: nil)
        wait(for: [another], timeout: 5)
        XCTAssertNotEqual(listener.reading, first)

        listener.cover(for: 1.0)
        XCTAssertNil(listener.reading.frequency, "covered, it has to forget what it was hearing at once")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(listener.reading.frequency, "it heard something while it was meant to be covered")
        let again = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in listener.reading.frequency != nil }, object: nil)
        wait(for: [again], timeout: 5)

        listener.stop()
        XCTAssertEqual(listener.state, .idle)
        XCTAssertNil(listener.reading.frequency)
    }
}
