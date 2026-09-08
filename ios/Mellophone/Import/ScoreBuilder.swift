import CoreGraphics
import Foundation

/// Turns positioned glyphs and paths into music.
///
/// Everything upstream of this file is deliberately ignorant: PDFGlyphReader
/// knows PDF, MusicFontTable knows codepoints, StaffFitter knows rectangles.
/// All of the music knowledge is here, and so is all of the risk, because a
/// staff position read one line out transposes the whole part and still sounds
/// like music.
///
/// **Coordinates.** PDF user space has y increasing UPWARD and PDFGlyphReader
/// reports it raw, so `StaffSystem.bottomLineY` is the smallest y and a LARGER
/// step is a HIGHER pitch. Measured rather than assumed: the treble clef glyph's
/// origin sits 2.00 steps above the bottom line in Opus (Sibelius) and in Leland
/// (MuseScore) alike, and a treble clef sits on G4, the second line from the
/// bottom. Rendering the pages confirms it a second way, since the staff with
/// the title and measure 1 on it is the one with the LARGEST y.
///
/// This task reads pitch. Durations are the notehead's ceiling (a black head is
/// "a quarter or shorter") and onsets simply run in x order; flags, beams, dots,
/// rests and ties are Task 5 and the measure-sum validator is Task 6.
enum ScoreBuilder {

    // MARK: - Thresholds, all measured against the charts in issue #19

    /// How far outside its own band a glyph may sit and still belong to a staff.
    /// Assignment is nearest-wins rather than "inside a widened band": PEAK's
    /// staves are only 20 half-spaces apart edge to edge, so a fixed widening
    /// leaves a dead zone that swallows ledger-line notes, while Florida's are
    /// 37 apart, where nearest-wins cannot reach the wrong staff. Beams sit at
    /// step 11.5 and articulations at 15.1, so this has to clear both.
    private static let assignmentReach: Double = 12
    /// An accidental this close to the left of a notehead at the same step is
    /// that notehead's, not the key signature's. Measured on Florida page 1
    /// system 1, where one chord carries a sharp 4.26 half-spaces out and a
    /// natural 1.87 out, both at their own notehead's exact y.
    private static let inlineAccidentalReach: Double = 6
    /// Two key signature accidentals are spaced this closely. PEAK's four flats
    /// are 5.18 points apart, which is 2.25 half-spaces. The Florida bottom
    /// system's courtesy flat is 4.8 half-spaces from the key flat, which is
    /// what this rejects.
    private static let keySignatureStride: Double = 3.5
    /// Two barlines closer than this are one barline drawn twice: a repeat or a
    /// double bar. Measured at 1.47 half-spaces (Florida) and 1.06 (PEAK).
    private static let barlineMergeReach: Double = 3
    /// A barline spans the staff exactly. Both ends must land this close to the
    /// staff's own ends, in half-spaces. Measured: PEAK 0.00 to 8.00, Florida
    /// -0.11 to 8.11. Stems in the same band run -2.50 to 4.66 and 2.32 to
    /// 10.00, and a multi-measure rest's end caps run 2.00 to 6.00.
    private static let barlineEndReach: Double = 0.5
    /// Nothing wider than this is a barline.
    private static let barlineMaxWidth: Double = 2.0
    /// Two time signature digits are stacked, so they share an x. Measured at
    /// 0.00 apart (PEAK) and 0.65 (Florida).
    private static let timeSignaturePairReach: Double = 1.5

    /// Diatonic index of a pitch: `octave * 7 + letter`, C = 0 through B = 6.
    /// One diatonic step is one staff step, which is the whole point of counting
    /// in this space rather than in semitones.
    private static let letterNames = ["C", "D", "E", "F", "G", "A", "B"]
    private static let letterSemitones = [0, 2, 4, 5, 7, 9, 11]
    /// The order accidentals are added to a key signature, as letter indices.
    private static let flatOrder = [6, 2, 5, 1, 4, 0, 3]   // B E A D G C F
    private static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]  // F C G D A E B
    /// A treble clef's glyph origin sits on G4, a bass clef's on F3. The treble
    /// value is measured in both engravers; the bass value is the convention and
    /// is untested, because every part in issue #19 is treble.
    private static let gClefDiatonic = 4 * 7 + 4
    private static let fClefDiatonic = 3 * 7 + 3

    // MARK: - Entry point

    static func build(pages: [PageGeometry], font: MusicFontTable) -> Score {
        var events: [ScoreEvent] = []
        var unreadable: [UInt32] = []
        var voiceCount = 0
        var measure = 1
        var onset: Double = 0
        var firstHead: (key: Int, time: (beats: Int, unit: Int))?
        var currentTime = (beats: 4, unit: 4)

        for (pageIndex, page) in pages.enumerated() {
            let systems = StaffFitter.systems(in: page.paths)
            guard !systems.isEmpty else {
                Log.score.error("[IMPORT] page \(pageIndex + 1, privacy: .public) has no staff systems, \(page.glyphs.count, privacy: .public) glyphs dropped")
                #if DEBUG
                FileLog.write("[IMPORT] page \(pageIndex + 1) has no staff systems")
                #endif
                continue
            }

            let assigned = assign(glyphs: page.glyphs, to: systems)
            for (systemIndex, system) in systems.enumerated() {
                let glyphs = assigned[systemIndex]
                // A meter is stated once and holds until it changes, so a system
                // with no digits in its head inherits rather than resetting to
                // 4/4. Only the FIRST system of a part is ever really 4/4 by
                // default. A key signature is restated on every system, so it
                // carries no equivalent and an empty run really is C major.
                let head = readHead(glyphs: glyphs, system: system, font: font,
                                    inheritedTime: currentTime)
                currentTime = head.timeSignature
                if firstHead == nil { firstHead = (head.keySignature, head.timeSignature) }

                let barlines = barlineXs(in: page.paths, system: system)
                let read = readNotes(glyphs: glyphs, system: system, head: head, font: font,
                                     barlines: barlines, measure: &measure, onset: &onset)
                events.append(contentsOf: read.events)
                voiceCount = max(voiceCount, read.voiceCount)
                unreadable.append(contentsOf: read.unreadable)
            }
        }

        let head = firstHead ?? (0, (4, 4))
        if events.isEmpty {
            Log.score.error("[IMPORT] read \(pages.count, privacy: .public) pages and found no notes")
            #if DEBUG
            FileLog.write("[IMPORT] read \(pages.count) pages and found no notes")
            #endif
        } else {
            let outOfRange = events.filter { $0.outOfRangeName != nil }.count
            Log.score.info("[IMPORT] built \(events.count, privacy: .public) events over \(measure, privacy: .public) measures, key \(head.key, privacy: .public), \(head.time.beats, privacy: .public)/\(head.time.unit, privacy: .public), \(voiceCount, privacy: .public) voices, \(outOfRange, privacy: .public) out of range, \(Set(unreadable).count, privacy: .public) unreadable codepoints")
        }

        return Score(events: events,
                     timeSignature: head.time,
                     keySignature: head.key,
                     voiceCount: voiceCount,
                     suspectMeasures: [],
                     unreadableSymbols: Array(Set(unreadable)).sorted())
    }

    // MARK: - Stage 1: which staff does each glyph belong to

    /// Nearest band wins, capped at `assignmentReach`. Glyphs from a non-music
    /// font are dropped here, which is what removes the title, the tempo mark
    /// and the rehearsal letters without any special case for them.
    private static func assign(glyphs: [PlacedGlyph], to systems: [StaffSystem]) -> [[PlacedGlyph]] {
        var buckets = [[PlacedGlyph]](repeating: [], count: systems.count)
        var dropped = 0
        for glyph in glyphs {
            guard MusicFontTable.forFont(glyph.font) != nil else { continue }
            var best: (index: Int, distance: Double)?
            for (index, system) in systems.enumerated() {
                guard glyph.x >= system.xRange.lowerBound - system.halfSpace,
                      glyph.x <= system.xRange.upperBound + system.halfSpace else { continue }
                let below = system.bottomLineY - glyph.y
                let above = glyph.y - system.lineYs[4]
                let distance = max(0, max(below, above)) / system.halfSpace
                if distance <= assignmentReach, best == nil || distance < best!.distance {
                    best = (index, distance)
                }
            }
            if let best { buckets[best.index].append(glyph) } else { dropped += 1 }
        }
        if dropped > 0 {
            Log.score.info("[IMPORT] \(dropped, privacy: .public) music glyphs sat too far from any staff and were dropped")
        }
        for index in buckets.indices { buckets[index].sort { $0.x < $1.x } }
        return buckets
    }

    // MARK: - Stage 2: the head of a system

    private struct Head {
        /// Diatonic index of the pitch sitting on the staff's bottom line.
        let bottomDiatonic: Int
        let keySignature: Int
        let timeSignature: (beats: Int, unit: Int)
        /// Glyph indices the head consumed, so the note reader skips them.
        let consumed: Set<Int>
    }

    private static func readHead(glyphs: [PlacedGlyph], system: StaffSystem,
                                 font: MusicFontTable,
                                 inheritedTime: (beats: Int, unit: Int)) -> Head {
        var consumed = Set<Int>()
        var bottomDiatonic = gClefDiatonic - 2   // no clef found: assume treble

        var index = 0
        var clefX: Double?
        while index < glyphs.count {
            let symbol = font.symbol(for: glyphs[index].scalar)
            if symbol == .gClef || symbol == .fClef {
                let step = staffStep(of: glyphs[index], on: system)
                let anchor = symbol == .gClef ? gClefDiatonic : fClefDiatonic
                bottomDiatonic = anchor - step
                consumed.insert(index)
                clefX = glyphs[index].x
                break
            }
            index += 1
        }
        if clefX == nil {
            Log.score.error("[IMPORT] no clef on a staff at y \(system.bottomLineY, privacy: .public), reading it as treble")
        }

        // The key signature run. It ends at the first notehead, rest or digit,
        // and also at the first accidental that breaks the canonical order or
        // sits too far from the one before it. Both guards fire independently on
        // the Florida bottom system, where a courtesy flat follows the key flat
        // on the SAME line rather than on the E line a second flat would use.
        var keyCount = 0
        var keySign = 0
        var previousX = clefX ?? -.greatestFiniteMagnitude
        var cursor = index + 1
        while cursor < glyphs.count {
            let glyph = glyphs[cursor]
            let symbol = font.symbol(for: glyph.scalar)
            if symbol.isNotehead { break }
            if case .rest = symbol { break }
            if case .timeSigDigit = symbol { break }
            // A cancellation natural at a key change belongs to the head but
            // adds nothing to the count.
            if symbol == .natural, !isInline(glyphs[cursor], among: glyphs, system: system, font: font) {
                consumed.insert(cursor)
                previousX = glyph.x
                cursor += 1
                continue
            }
            guard symbol == .sharp || symbol == .flat else { cursor += 1; continue }
            guard !isInline(glyph, among: glyphs, system: system, font: font) else { break }
            let sign = symbol == .sharp ? 1 : -1
            guard keyCount == 0 || sign == keySign else { break }
            guard (glyph.x - previousX) / system.halfSpace <= keySignatureStride || keyCount == 0 else { break }
            let letter = mod7(bottomDiatonic + staffStep(of: glyph, on: system))
            let expected = (sign > 0 ? sharpOrder : flatOrder)[keyCount]
            guard letter == expected else { break }
            keySign = sign
            keyCount += 1
            consumed.insert(cursor)
            previousX = glyph.x
            cursor += 1
        }

        let time = readTimeSignature(glyphs: glyphs, from: cursor, system: system,
                                     font: font, inherited: inheritedTime, consumed: &consumed)
        return Head(bottomDiatonic: bottomDiatonic,
                    keySignature: keySign * keyCount,
                    timeSignature: time,
                    consumed: consumed)
    }

    /// Digit glyphs are a time signature ONLY inside the staff and in the head.
    ///
    /// The same codepoints carry measure numbers, multi-measure rest counts and
    /// tuplet numbers, which on PEAK mello.pdf outnumber the real time signature
    /// digits 35 to 8 and sit above or below the staff at step 11.10. Reading
    /// one of those as a meter makes every measure fail Task 6's sum check,
    /// which turns the validator from signal into noise.
    private static func readTimeSignature(glyphs: [PlacedGlyph], from start: Int,
                                          system: StaffSystem, font: MusicFontTable,
                                          inherited: (beats: Int, unit: Int),
                                          consumed: inout Set<Int>) -> (beats: Int, unit: Int) {
        var digits: [(index: Int, x: Double, step: Double, value: Int)] = []
        var cursor = start
        while cursor < glyphs.count {
            let glyph = glyphs[cursor]
            let symbol = font.symbol(for: glyph.scalar)
            if symbol.isNotehead { break }
            if case .rest = symbol { break }
            if case .timeSigDigit(let value) = symbol {
                let step = (glyph.y - system.bottomLineY) / system.halfSpace
                if step >= 0, step <= 8 {
                    digits.append((cursor, glyph.x, step, value))
                }
            }
            cursor += 1
        }
        for lower in digits {
            guard let upper = digits.first(where: {
                abs($0.x - lower.x) < timeSignaturePairReach && $0.step > lower.step + 1
            }) else { continue }
            consumed.insert(lower.index)
            consumed.insert(upper.index)
            return (beats: upper.value, unit: lower.value)
        }
        Log.score.debug("[IMPORT] no time signature inside the staff at y \(system.bottomLineY, privacy: .public), carrying \(inherited.beats, privacy: .public)/\(inherited.unit, privacy: .public) forward")
        return inherited
    }

    // MARK: - Stage 3: notes

    private static func readNotes(glyphs: [PlacedGlyph], system: StaffSystem, head: Head,
                                  font: MusicFontTable, barlines: [Double],
                                  measure: inout Int, onset: inout Double)
        -> (events: [ScoreEvent], voiceCount: Int, unreadable: [UInt32]) {

        var events: [ScoreEvent] = []
        var unreadable: [UInt32] = []
        var voiceCount = 0
        /// Inline accidentals hold to the end of their measure, keyed by
        /// diatonic index so they apply to that letter in THAT octave, which is
        /// the actual notation rule.
        var active: [Int: Accidental] = [:]

        // Group noteheads by x. A shared x is a chord, and on a horn part that
        // is divisi, which is how the Florida chart is written throughout.
        var groups: [Double: [PlacedGlyph]] = [:]
        for (index, glyph) in glyphs.enumerated() {
            guard !head.consumed.contains(index) else { continue }
            let symbol = font.symbol(for: glyph.scalar)
            if case .unknown(let scalar) = symbol { unreadable.append(scalar) }
            guard symbol.isNotehead else { continue }
            groups[(glyph.x * 10).rounded() / 10, default: []].append(glyph)
        }

        var barlineCursor = 0
        for x in groups.keys.sorted() {
            while barlineCursor < barlines.count, barlines[barlineCursor] < x {
                measure += 1
                active.removeAll()
                barlineCursor += 1
            }
            // Highest pitch is voice 0, and in this frame the highest pitch is
            // the LARGEST y.
            let heads = groups[x]!.sorted { $0.y > $1.y }
            voiceCount = max(voiceCount, heads.count)
            var longest: Double = 0
            for (voice, glyph) in heads.enumerated() {
                let step = staffStep(of: glyph, on: system)
                let diatonic = head.bottomDiatonic + step
                if let inline = inlineAccidental(for: glyph, step: step, among: glyphs,
                                                 head: head, system: system, font: font) {
                    active[diatonic] = inline
                }
                let accidental = active[diatonic] ?? keyAccidental(for: diatonic, key: head.keySignature)
                let name = spell(diatonic: diatonic, accidental: accidental)
                let value = font.symbol(for: glyph.scalar).impliedValue ?? .quarter
                let beats = value.beats(unit: head.timeSignature.unit)
                longest = max(longest, beats)
                let resolved = resolve(name: name, diatonic: diatonic, accidental: accidental)
                if resolved == nil {
                    let bar = measure
                    Log.score.info("[IMPORT] \(name, privacy: .public) in measure \(bar, privacy: .public) is outside F#3 to C6, kept as a named silent event")
                }
                events.append(ScoreEvent(note: resolved,
                                         writtenName: name,
                                         outOfRangeName: resolved == nil ? name : nil,
                                         onsetBeats: onset,
                                         durationBeats: beats,
                                         measure: measure,
                                         voice: voice))
            }
            onset += longest
        }
        // Trailing barlines still end their measure, or the first group of the
        // next system lands in the one that just closed.
        while barlineCursor < barlines.count {
            measure += 1
            active.removeAll()
            barlineCursor += 1
        }
        return (events, voiceCount, unreadable)
    }

    // MARK: - Accidentals

    /// True when this accidental is attached to a notehead rather than standing
    /// in a key signature: the nearest notehead to its right, at its own step,
    /// is within reach.
    private static func isInline(_ accidental: PlacedGlyph, among glyphs: [PlacedGlyph],
                                 system: StaffSystem, font: MusicFontTable) -> Bool {
        let step = staffStep(of: accidental, on: system)
        return glyphs.contains { glyph in
            font.symbol(for: glyph.scalar).isNotehead
                && glyph.x > accidental.x
                && (glyph.x - accidental.x) / system.halfSpace <= inlineAccidentalReach
                && staffStep(of: glyph, on: system) == step
        }
    }

    private static func inlineAccidental(for notehead: PlacedGlyph, step: Int,
                                         among glyphs: [PlacedGlyph], head: Head,
                                         system: StaffSystem, font: MusicFontTable) -> Accidental? {
        var best: (distance: Double, accidental: Accidental)?
        for (index, glyph) in glyphs.enumerated() {
            guard !head.consumed.contains(index) else { continue }
            let accidental: Accidental
            switch font.symbol(for: glyph.scalar) {
            case .sharp: accidental = .sharp
            case .flat: accidental = .flat
            case .natural: accidental = .natural
            default: continue
            }
            guard glyph.x < notehead.x, staffStep(of: glyph, on: system) == step else { continue }
            let distance = (notehead.x - glyph.x) / system.halfSpace
            guard distance <= inlineAccidentalReach else { continue }
            if best == nil || distance < best!.distance { best = (distance, accidental) }
        }
        return best?.accidental
    }

    private static func keyAccidental(for diatonic: Int, key: Int) -> Accidental {
        guard key != 0 else { return .natural }
        let order = key > 0 ? sharpOrder : flatOrder
        let letter = mod7(diatonic)
        return order.prefix(abs(key)).contains(letter) ? (key > 0 ? .sharp : .flat) : .natural
    }

    // MARK: - Spelling and lookup

    private static func spell(diatonic: Int, accidental: Accidental) -> String {
        "\(letterNames[mod7(diatonic)])\(accidental.rawValue)\(diatonic / 7)"
    }

    /// The app's Note for a written pitch, by enharmonic equivalence when the
    /// exact spelling has no row.
    ///
    /// NoteData stores five sharps and spells everything else flat, so
    /// `Note.named("G#4")` is nil even though a horn plays G#4 with 2+3. Letting
    /// that fall through to "out of range" would grey out and SILENCE a note
    /// that is comfortably inside the instrument, and Florida page 1 has exactly
    /// that sharp on it. Only a pitch with no row at its PITCH is out of range.
    private static func resolve(name: String, diatonic: Int, accidental: Accidental) -> Note? {
        if let exact = Note.named(name) { return exact }
        let semitone = letterSemitones[mod7(diatonic)]
            + (accidental == .sharp ? 1 : accidental == .flat ? -1 : 0)
        let midi = semitone + (diatonic / 7 + 1) * 12
        let candidates = Note.all.filter { midiNumber(of: $0) == midi }
        return candidates.first { $0.accidental == accidental } ?? candidates.first
    }

    /// Parsed from the row's own name rather than from its frequency, so no
    /// floating point rounding sits between a note and its identity.
    private static func midiNumber(of note: Note) -> Int? {
        var characters = Array(note.name)
        guard let letter = letterNames.firstIndex(of: String(characters.removeFirst())) else { return nil }
        var semitone = letterSemitones[letter]
        if characters.first == "#" { semitone += 1; characters.removeFirst() }
        else if characters.first == "b" { semitone -= 1; characters.removeFirst() }
        guard let octave = Int(String(characters)) else { return nil }
        return semitone + (octave + 1) * 12
    }

    // MARK: - Geometry

    /// Diatonic steps above the staff's bottom line. Rounded, because a notehead
    /// sits either on a line or exactly halfway between two and anything else is
    /// engraver noise.
    private static func staffStep(of glyph: PlacedGlyph, on system: StaffSystem) -> Int {
        Int(((glyph.y - system.bottomLineY) / system.halfSpace).rounded())
    }

    /// A barline spans the staff exactly, top end and bottom end. A stem shares
    /// its width and roughly its height but starts at a notehead, and a
    /// multi-measure rest's end caps sit wholly inside the staff, so testing
    /// BOTH ends is what tells the three apart.
    private static func barlineXs(in paths: [PlacedPath], system: StaffSystem) -> [Double] {
        let reach = barlineEndReach * system.halfSpace
        let candidates = paths
            .filter { path in
                Double(path.bounds.width) <= barlineMaxWidth
                    && abs(Double(path.bounds.minY) - system.bottomLineY) <= reach
                    && abs(Double(path.bounds.maxY) - system.lineYs[4]) <= reach
                    && Double(path.bounds.midX) >= system.xRange.lowerBound - system.halfSpace
                    && Double(path.bounds.midX) <= system.xRange.upperBound + system.halfSpace
            }
            .map { Double($0.bounds.midX) }
            .sorted()

        // A repeat or a double bar is two rules a point or two apart. Left
        // separate they would open an empty measure between them.
        var merged: [Double] = []
        for x in candidates {
            if let last = merged.last, (x - last) / system.halfSpace < barlineMergeReach { continue }
            merged.append(x)
        }
        return merged
    }

    private static func mod7(_ value: Int) -> Int { ((value % 7) + 7) % 7 }
}
