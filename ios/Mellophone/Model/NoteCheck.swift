import Foundation

/// One note a student is checking themselves against, and what to say about
/// the sound that came back.
///
/// Everything here is arithmetic on two numbers, the pitch that was wanted and
/// the pitch that was heard, so that all of it can be tested without a
/// microphone. `PitchListener` supplies the second number and knows nothing
/// about notes.
struct NoteCheck: Equatable {
    /// The note as the PAGE spells it, which is what the student is reading.
    let writtenName: String
    /// The literal frequency of that name, the one the app's own audio uses.
    let writtenFrequency: Double
    let instrument: Instrument

    /// What the horn actually puts into the room for this note.
    ///
    /// THE reason this type exists. Everywhere else in the app a written C5 is
    /// 523 Hz, because nothing else has ever had to agree with a real
    /// instrument. A mellophone playing that C5 sounds the F below it, 349 Hz,
    /// and a microphone hears 349. Compare against the written number and
    /// every correct note a student plays is reported a fifth flat.
    var soundingFrequency: Double {
        writtenFrequency * pow(2, -Double(instrument.transpositionSemitones) / 12)
    }

    /// The concert name of that sound, for the one line that explains why the
    /// reference tone here is lower than the same note tapped in the list.
    ///
    /// In flats, which is how a band names concert pitch: "concert Db", never
    /// "concert C sharp".
    var soundingName: String {
        Self.name(ofSemitone: Self.semitone(of: soundingFrequency), spelling: Self.concertSpelling)
    }

    /// How far the reference tone's filter is allowed to close, in Hz.
    ///
    /// The tone played on this screen is the SOUNDING pitch, down to 82 Hz on
    /// a euphonium, out of a phone speaker that makes very little under about
    /// 300. See `TonePlayer.render(brightnessFloor:)`. At 700 the quietest
    /// reference note on any instrument keeps its overtones up to the eighth
    /// on a low E, and notes above the F over middle C are not changed at
    /// all, since their filter already sits higher than this.
    static let referenceBrightnessFloor = 700.0

    // MARK: - Judging

    /// Inside this many cents either way is "in tune".
    ///
    /// 20 and not 5. This is a student checking they have the right note and
    /// are roughly on it, with a horn whose tuning slide the phone knows
    /// nothing about, and a tuner strict enough for a studio would tell them
    /// they are wrong all day.
    static let inTuneCents = 20.0

    enum Verdict: Equatable {
        /// Nothing that is a note is coming in.
        case nothing
        case inTune(cents: Double)
        /// The right note, low by this much. Always positive.
        case flat(cents: Double)
        case sharp(cents: Double)
        /// A different note altogether, named as the student would read it.
        /// `sameValves` is the brass miss: the right fingering and the wrong
        /// partial, which no amount of checking the valves will find.
        case wrongNote(writtenName: String, sameValves: Bool, tooHigh: Bool)
    }

    func verdict(heard: Double?) -> Verdict {
        guard let heard, heard > 0 else { return .nothing }
        let cents = Pitch.cents(heard, soundingFrequency)
        // Past half a semitone it is nearer to some other note than to this
        // one, and "you are 180 cents sharp" is not something anyone can act
        // on. Say which note it is.
        guard abs(cents) < 50 else {
            let name = writtenName(ofHeard: heard)
            let mine = Fingering.value(for: writtenName, on: instrument)
            let theirs = Fingering.value(for: name, on: instrument)
            return .wrongNote(writtenName: name, sameValves: mine != nil && mine == theirs, tooHigh: cents > 0)
        }
        if abs(cents) <= Self.inTuneCents { return .inTune(cents: cents) }
        return cents < 0 ? .flat(cents: -cents) : .sharp(cents: cents)
    }

    /// How far off the target, in cents, for the needle. Nil with nothing to
    /// hear.
    func cents(heard: Double?) -> Double? {
        guard let heard, heard > 0 else { return nil }
        return Pitch.cents(heard, soundingFrequency)
    }

    /// The written note a sounding pitch is, on this instrument.
    func writtenName(ofHeard heard: Double) -> String {
        Self.name(ofSemitone: Self.semitone(of: heard) + instrument.transpositionSemitones)
    }

    // MARK: - Words

    /// What the screen says about a verdict: one line to read at arm's length
    /// with a horn up, and one under it for when the horn comes down.
    ///
    /// Kept here, with the judging, so the sentence a student is told can be
    /// tested against the sound that produced it.
    func words(for verdict: Verdict, confirmed: Bool) -> (headline: String, detail: String) {
        let fingering = Fingering.value(for: writtenName, on: instrument)
        switch verdict {
        case .nothing:
            return confirmed
                ? ("That's it", "\(writtenName)\(fingering.map { ", \($0)" } ?? ""). Play it again to check it again.")
                : ("Play it and hold it", "")
        case .inTune:
            return confirmed
                ? ("That's it", "\(writtenName)\(fingering.map { ", \($0)" } ?? "")")
                : ("That's \(writtenName)", "Hold it steady")
        case .flat(let cents):
            return ("Right note, flat", "\(Int(cents.rounded())) cents low")
        case .sharp(let cents):
            return ("Right note, sharp", "\(Int(cents.rounded())) cents high")
        case .wrongNote(let name, let sameValves, let tooHigh):
            let aim = "Aim \(tooHigh ? "lower" : "higher")."
            if sameValves {
                // Said first and plainly, because it is the answer a student
                // will not find by looking at their fingers.
                return ("That's \(name)", "Right valves, wrong note. \(aim)")
            }
            return ("That's \(name)", "\(writtenName) is \(fingering ?? "not on this horn"). \(aim)")
        }
    }

    // MARK: - Names

    /// MIDI numbering: A4 is 69.
    private static func semitone(of frequency: Double) -> Int {
        Int((69 + 12 * log2(frequency / 440)).rounded())
    }

    /// Spelled the way the fingering chart spells the twelve, so a name that
    /// comes out of here can be looked up in it.
    private static let chartSpelling = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let concertSpelling = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    private static func name(ofSemitone value: Int, spelling: [String] = chartSpelling) -> String {
        let pitchClass = ((value % 12) + 12) % 12
        // Floor division, so a note below C0 would still get the right octave.
        let octave = Int((Double(value) / 12).rounded(.down)) - 1
        return "\(spelling[pitchClass])\(octave)"
    }
}

/// Whether the student has HELD the note, as opposed to passing through it.
///
/// A slide up to a pitch crosses "in tune" for a tenth of a second on the way,
/// and that is not having played it. Counted in readings and not in seconds
/// because the listener's readings are the only clock this has; they come at
/// about ten a second.
struct NoteConfirmation: Equatable {
    static let readingsNeeded = 6

    private(set) var streak = 0
    private(set) var isConfirmed = false

    /// Returns true on the reading that confirms it, once, so the caller can
    /// buzz the phone without buzzing it ten times a second.
    @discardableResult
    mutating func take(_ verdict: NoteCheck.Verdict) -> Bool {
        if case .inTune = verdict {
            streak += 1
            if streak >= Self.readingsNeeded, !isConfirmed {
                isConfirmed = true
                return true
            }
        } else {
            streak = 0
            // Silence is the student taking a breath. It does not take the
            // tick away. A WRONG sound does, because they are trying again.
            if verdict != .nothing { isConfirmed = false }
        }
        return false
    }
}
