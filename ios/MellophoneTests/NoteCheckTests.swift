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

        // Four good readings, a wobble, four more: never six in a row.
        var wobbly = NoteConfirmation()
        for _ in 0..<4 { wobbly.take(.inTune(cents: 0)) }
        wobbly.take(.sharp(cents: 25))
        for _ in 0..<4 { wobbly.take(.inTune(cents: 0)) }
        XCTAssertFalse(wobbly.isConfirmed)
    }
}

/// The half that listens: is this block of audio a note, which one, and what
/// does it look like.
final class PitchAnalysisTests: XCTestCase {

    private let rate = 48_000.0

    private var format: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)! }

    /// One listener's worth of samples out of the steady middle of a note the
    /// app's own renderer made.
    private func window(of frequency: Double, volume: Double = 0.4) throws -> [Double] {
        let buffer = try XCTUnwrap(TonePlayer.render(frequency: frequency, duration: 0.6, volume: volume, format: format))
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        let from = Int(0.25 * rate)
        return (from..<(from + PitchListener.window)).map { Double(data[$0]) }
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
    /// blocks, the ring, the detector, the median, the publish.
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
