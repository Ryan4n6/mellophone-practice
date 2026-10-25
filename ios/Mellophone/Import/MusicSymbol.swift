import Foundation

/// A duration, as a fraction of a whole note.
///
/// Rational rather than floating point because the measure-sum check compares
/// these for equality. A dotted half is exactly three quarters here; as a Double
/// it is three quarters plus whatever the last addition left behind, and a
/// measure that should sum would then fail by a hair and get flagged for nothing.
struct NoteValue: Equatable, Hashable {
    let numerator: Int
    let denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        let g = NoteValue.gcd(abs(numerator), abs(denominator))
        self.numerator = numerator / max(g, 1)
        self.denominator = denominator / max(g, 1)
    }

    static let whole = NoteValue(1, 1)
    static let half = NoteValue(1, 2)
    static let quarter = NoteValue(1, 4)
    static let eighth = NoteValue(1, 8)
    static let sixteenth = NoteValue(1, 16)

    /// One augmentation dot adds half the value again, two adds another quarter
    /// on top of that. Each dot halves what the previous one added, which is why
    /// this accumulates rather than multiplying by a table of constants.
    func dotted(_ dots: Int) -> NoteValue {
        var total = self
        var addition = self
        for _ in 0..<dots {
            addition = NoteValue(addition.numerator, addition.denominator * 2)
            total = total + addition
        }
        return total
    }

    /// This value played `normal` in the time of `actual`: a triplet eighth is
    /// an eighth times 2/3. Kept rational for the same reason as everything
    /// else here, so three triplet eighths sum to exactly one quarter (#39).
    func tuplet(actual: Int, normal: Int) -> NoteValue {
        NoteValue(numerator * normal, denominator * actual)
    }

    static func + (a: NoteValue, b: NoteValue) -> NoteValue {
        NoteValue(a.numerator * b.denominator + b.numerator * a.denominator,
                  a.denominator * b.denominator)
    }

    /// In beats, given which note value gets the beat: 4 for a quarter, 2 for a
    /// half, 8 for an eighth. That is the denominator of the time signature.
    func beats(unit: Int) -> Double {
        Double(numerator) / Double(denominator) * Double(unit)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

/// What a glyph means, independent of which engraver drew it.
enum MusicSymbol: Equatable {
    case noteheadBlack
    case noteheadHalf
    case noteheadWhole
    /// An x notehead on a stem: a hand clap (#53). Read for its rhythm the
    /// way a black head is, with stems, beams, flags and dots, and never for
    /// its pitch.
    case noteheadX
    case gClef
    case fClef
    case sharp
    case flat
    case natural
    case augmentationDot
    case flag(count: Int, up: Bool)
    case rest(NoteValue)
    case timeSigDigit(Int)
    /// Accent, tenuto, marcato, staccato.
    ///
    /// Carried rather than dropped because an articulation rides a notehead
    /// exactly the way an augmentation dot does. In Opus the staccato dot is
    /// U+02D9 and the augmentation dot is U+002E, and a reader with no case for
    /// the first will reach for the nearest thing it has and lengthen the note.
    /// ScoreBuilder ignores these. It just must not mistake them.
    case articulation
    /// One of the two dots of a repeat sign (#46). Which side of its barline
    /// the pair sits on says whether the repeat starts or ends there.
    case repeatDot
    case unknown(UInt32)

    var isNotehead: Bool {
        self == .noteheadBlack || self == .noteheadHalf || self == .noteheadWhole || self == .noteheadX
    }

    /// The longest duration a notehead ALONE can prove.
    ///
    /// A black notehead is a quarter or anything shorter, and only a flag or a
    /// beam decides which, so this returns the ceiling and the rhythm stage
    /// narrows it. Treating this as the answer makes every beamed run play at
    /// four times its written length.
    var impliedValue: NoteValue? {
        switch self {
        case .noteheadWhole: return .whole
        case .noteheadHalf: return .half
        case .noteheadBlack, .noteheadX: return .quarter
        default: return nil
        }
    }
}
