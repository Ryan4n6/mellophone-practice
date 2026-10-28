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
    /// Which question is being asked of the sound. See `Purpose`.
    var purpose: Purpose = .rightNote

    /// The two things a student holds a note up to the phone for.
    enum Purpose: Equatable {
        /// "Is this the note on the page?" A note out of a chart.
        case rightNote
        /// "Is my horn in tune?" The tuner (#32): the note is not in doubt,
        /// the tuning slide is.
        case tuning
    }

    /// What the horn actually puts into the room for this note.
    ///
    /// THE reason this type exists. Everywhere else in the app a written C5 is
    /// 523 Hz, because nothing else has ever had to agree with a real
    /// instrument. A mellophone playing that C5 sounds the F below it, 349 Hz,
    /// and a microphone hears 349. Compare against the written number and
    /// every correct note a student plays is reported a fifth flat.
    var soundingFrequency: Double {
        instrument.sounding(writtenFrequency)
    }

    /// The concert name of that sound, for the one line under "Hear it" that
    /// says which pitch is being played.
    ///
    /// In flats, which is how a band names concert pitch: "concert Db", never
    /// "concert C sharp".
    var soundingName: String {
        Self.name(ofSemitone: Self.semitone(of: soundingFrequency), spelling: Self.concertSpelling)
    }

    /// How far the filter is allowed to close on a tone at SOUNDING pitch, in
    /// Hz. A chart is played with the same floor (#24), for the same reason.
    ///
    /// The tone played on this screen is the SOUNDING pitch, down to 82 Hz on
    /// a euphonium, out of a phone speaker that makes very little under about
    /// 300. See `TonePlayer.render(brightnessFloor:)`. At 700 the quietest
    /// reference note on any instrument keeps its overtones up to the eighth
    /// on a low E. Notes sounding B4 (494 Hz) and up are not changed at all,
    /// since the filter settles at one and a half times the pitch and that is
    /// already over 700 there. Under B4 the held part of every note is
    /// brighter than the plain tone, the middle of a mellophone part included
    /// (#37 corrected this from "above the F over middle C").
    static let referenceBrightnessFloor = 700.0

    // MARK: - Judging

    /// Inside this many cents either way is "in tune".
    ///
    /// 20 and not 5. This is a student checking they have the right note and
    /// are roughly on it, with a horn whose tuning slide the phone knows
    /// nothing about, and a tuner strict enough for a studio would tell them
    /// they are wrong all day.
    static let inTuneCents = 20.0

    /// The same band for the tuner, half the width.
    ///
    /// Tuning is the one time the small number is the point: ten cents out
    /// against the horn next to you is a beat twice a second on a concert F,
    /// which a section can hear. Not five either. The detector reads a steady
    /// tone to a tenth of a cent (measured, see `ios/README.md`), so the
    /// limit is not the phone, it is that a student's held note wanders by
    /// more than five and a band that narrow would never stay lit. The number
    /// is on the screen the whole time for anyone who wants it nearer.
    static let tuningCents = 10.0

    /// How far out still counts as in tune, for the question being asked.
    var tolerance: Double {
        purpose == .tuning ? Self.tuningCents : Self.inTuneCents
    }

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
        if abs(cents) <= tolerance { return .inTune(cents: cents) }
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
    ///
    /// Every line is one whole sentence for the catalog (#67), never pieces
    /// glued together: Spanish and French put the note, the number and the
    /// direction in different places, and agree "bajo" and "grave" with what
    /// they describe. Note names are shown in `naming`.
    func words(for verdict: Verdict, confirmed: Bool,
               naming: NoteNaming = .current) -> (headline: String, detail: String) {
        if purpose == .tuning, let tuning = tuningWords(for: verdict, confirmed: confirmed) { return tuning }
        let note = naming.show(writtenName)
        let valves = Fingering.value(for: writtenName, on: instrument).map(Fingering.shown)
        switch verdict {
        case .nothing:
            guard confirmed else { return (String(localized: "Play it and hold it"), "") }
            return (String(localized: "That's it"), valves.map { String(localized: "\(note), \($0). Play it again to check it again.") }
                    ?? String(localized: "\(note). Play it again to check it again."))
        case .inTune:
            return confirmed
                ? (String(localized: "That's it"), valves.map { "\(note), \($0)" } ?? note)
                : (String(localized: "That's \(note)"), String(localized: "Hold it steady"))
        case .flat(let cents):
            return (String(localized: "Right note, flat"), String(localized: "\(Int(cents.rounded())) cents low"))
        case .sharp(let cents):
            return (String(localized: "Right note, sharp"), String(localized: "\(Int(cents.rounded())) cents high"))
        case .wrongNote(let name, let sameValves, let tooHigh):
            let heard = naming.show(name)
            if sameValves {
                // Said first and plainly, because it is the answer a student
                // will not find by looking at their fingers.
                return (String(localized: "That's \(heard)"), tooHigh
                        ? String(localized: "Right valves, wrong note. Aim lower.")
                        : String(localized: "Right valves, wrong note. Aim higher."))
            }
            guard let valves else {
                return (String(localized: "That's \(heard)"), tooHigh
                        ? String(localized: "\(note) is not on this horn. Aim lower.")
                        : String(localized: "\(note) is not on this horn. Aim higher."))
            }
            return (String(localized: "That's \(heard)"), tooHigh
                    ? String(localized: "\(note) is \(valves). Aim lower.")
                    : String(localized: "\(note) is \(valves). Aim higher."))
        }
    }

    /// What the tuner says, where it differs from the note check. Nil for a
    /// wrong note, which is the same news on either screen.
    ///
    /// The second line is the reason to have a tuner in THIS app and not send
    /// a student to any other: it says what to do with the slide. Sharp is a
    /// horn that is too short, so the slide comes out; flat, it goes in.
    /// "A little", because the commonest way to tune badly is to move it a
    /// centimetre, overshoot, and chase the needle back.
    private func tuningWords(for verdict: Verdict, confirmed: Bool) -> (headline: String, detail: String)? {
        switch verdict {
        case .nothing:
            return confirmed
                ? (String(localized: "In tune"), String(localized: "Leave the slide there. Play it again to check it again."))
                : (String(localized: "Play it and hold it"), "")
        case .inTune(let cents):
            let rounded = Int(abs(cents).rounded())
            let detail: String
            switch (rounded == 0, cents < 0, confirmed) {
            case (true, _, true): detail = String(localized: "Dead on. Leave the slide there.")
            case (true, _, false): detail = String(localized: "Dead on. Hold it steady.")
            case (false, true, true): detail = String(localized: "\(rounded) cents low. Leave the slide there.")
            case (false, true, false): detail = String(localized: "\(rounded) cents low. Hold it steady.")
            case (false, false, true): detail = String(localized: "\(rounded) cents high. Leave the slide there.")
            case (false, false, false): detail = String(localized: "\(rounded) cents high. Hold it steady.")
            }
            return (String(localized: "In tune"), detail)
        case .flat(let cents):
            return (String(localized: "Flat"), String(localized: "\(Int(cents.rounded())) cents low. Push your tuning slide in a little."))
        case .sharp(let cents):
            return (String(localized: "Sharp"), String(localized: "\(Int(cents.rounded())) cents high. Pull your tuning slide out a little."))
        case .wrongNote:
            return nil
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
///
/// Four, where it was six, because the listener now sits on a sound for two
/// readings before it shows the first one (`HeldPitch`, #34). The two
/// together are the same six tenths of a second from the start of the note
/// that a student was already being asked for, and no longer.
struct NoteConfirmation: Equatable {
    static let readingsNeeded = 4

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
