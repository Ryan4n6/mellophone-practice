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
    /// double bar. The gap distribution over PEAK's 213 barlines is bimodal
    /// with nothing in between: 49 gaps of 1.0 to 3.0 half-spaces (double bars
    /// and repeats), three at 4.00, 4.63 and 5.63 (repeats carrying dots), then
    /// nothing at all until 11.31 and 129 gaps above 12, which are real
    /// measures. The threshold goes in the empty band. At 3 it left three
    /// phantom measures in the count.
    private static let barlineMergeReach: Double = 8
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

    // Rhythm, all in half-spaces and all measured on the two charts in #19.

    /// A stem is never as wide as a half-space. Measured 0.00 to 0.38.
    private static let stemMaxWidth: Double = 1.0
    /// Measured stem lengths run 5.17 to 11.62. The floor sits below that so a
    /// stem shortened by a beam group still counts.
    private static let stemMinLength: Double = 3.5
    /// A stem sits at its notehead's own x when it points down and about 2.5
    /// across when it points up, which is the notehead's width.
    private static let stemAttachReach: Double = 3.5
    /// Beams: 2.75 to 14.94 wide and 0.63 to 2.60 thick across both charts. The
    /// width ceiling is what keeps a multi-measure rest's H-bar out, since that
    /// runs 20 to 66 wide at a similar thickness.
    private static let beamMinWidth: Double = 2.0
    private static let beamMaxWidth: Double = 15.0
    private static let beamMinThickness: Double = 0.6
    private static let beamMaxThickness: Double = 2.6
    /// How far from a stem tip a beam may sit and still be on it. Stacked beams
    /// are separate paths a beam's thickness apart, so this has to clear two of
    /// them.
    private static let beamTipReach: Double = 3.0
    /// A flag glyph's origin sits 5 half-spaces from its notehead, measured
    /// exactly on all 35 occurrences in PEAK.
    private static let flagMinOffset: Double = 3.0
    private static let flagMaxOffset: Double = 8.0
    /// An augmentation dot sits 3.28 half-spaces right of its notehead in
    /// Leland and 4.13 in Opus.
    private static let dotMinOffset: Double = 1.5
    private static let dotMaxOffset: Double = 6.0
    /// A multi-measure rest's end caps span steps 2 to 6 exactly, in both
    /// engravers.
    private static let endCapTolerance: Double = 0.4
    /// The bar count is centred over the H-bar. PEAK's measure numbers sit at
    /// the same height, so this window has to be tight.
    private static let countDigitReach: Double = 2.5
    /// Durations are built from exact rationals, so a measure that sums is exact
    /// and this only absorbs the conversion to beats.
    private static let sumTolerance: Double = 0.001

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
        /// How many beats each measure is supposed to hold. Kept per MEASURE
        /// rather than per score or even per staff, because a meter change does
        /// not wait for a new system: PEAK changes to 2/4 and back to 4/4 inside
        /// one staff. Checking every bar against one meter flagged 83 of its 256
        /// measures; checking each against its own flags 30.
        var meterOfMeasure: [Int: Double] = [:]
        /// The bottom number in force in each measure, kept beside the top one
        /// because playback needs it and the validator does not: a beat is a
        /// quarter in 4/4 and an eighth in 6/8, and only this says which.
        var unitOfMeasure: [Int: Int] = [:]

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
                currentTime = head.last
                // The meter to REPORT is the first one this staff actually
                // states, not the 4/4 the reader starts holding. meters[0] is
                // that inherited placeholder and meters[1], when it exists, is
                // the opening signature, since the list is sorted by x.
                if firstHead == nil {
                    let opening = head.meters.count > 1
                        ? (beats: head.meters[1].beats, unit: head.meters[1].unit)
                        : head.meter(at: -.greatestFiniteMagnitude)
                    firstHead = (head.keySignature, opening)
                }

                // Scope the paths to THIS staff first. A stem, a beam and a
                // rest's end cap are all pure shape tests with no y anchor of
                // their own, so handed the whole page they would happily count
                // the staff below's beams against this staff's notes.
                let mine = paths(of: page, for: system)
                let barlines = barlineXs(in: mine, system: system)
                let read = readNotes(glyphs: glyphs, system: system, head: head, font: font,
                                     paths: mine, barlines: barlines,
                                     measure: &measure, onset: &onset)
                meterOfMeasure.merge(read.meters) { _, later in later }
                unitOfMeasure.merge(read.units) { _, later in later }
                events.append(contentsOf: read.events)
                voiceCount = max(voiceCount, read.voiceCount)
                unreadable.append(contentsOf: read.unreadable)
            }
        }

        let head = firstHead ?? (0, (beats: 4, unit: 4))
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
                     suspectMeasures: suspectMeasures(in: events, meters: meterOfMeasure),
                     unreadableSymbols: Array(Set(unreadable)).sorted(),
                     beatUnits: unitOfMeasure)
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

    /// The paths whose vertical extent overlaps this staff's own band.
    ///
    /// Generous on purpose: beams and flags sit well outside the staff, and
    /// `assignmentReach` is the same distance the glyph assignment allows.
    private static func paths(of page: PageGeometry, for system: StaffSystem) -> [PlacedPath] {
        let low = system.bottomLineY - assignmentReach * system.halfSpace
        let high = system.lineYs[4] + assignmentReach * system.halfSpace
        return page.paths.filter {
            Double($0.bounds.maxY) >= low && Double($0.bounds.minY) <= high
        }
    }

    // MARK: - Stage 2: the head of a system

    private struct Head {
        /// Diatonic index of the pitch sitting on the staff's bottom line.
        let bottomDiatonic: Int
        let keySignature: Int
        /// Every meter in force across this staff, in x order, the first being
        /// whatever was inherited from the staff above.
        ///
        /// A list rather than one value because a meter change does NOT wait for
        /// a new system. PEAK mello.pdf carries exactly six in-staff time
        /// signature digits in the whole document, and four of them are on ONE
        /// staff: 2/4 at x 212 and back to 4/4 at x 286. Applying the first of
        /// those to the whole staff, and then to every staff after it, was worth
        /// 54 of the 83 measures the validator flagged, all of them bars holding
        /// a correct 4 beats against an expected 2.
        let meters: [(x: Double, beats: Int, unit: Int)]
        /// Glyph indices the head consumed, so the note reader skips them.
        let consumed: Set<Int>

        func meter(at x: Double) -> (beats: Int, unit: Int) {
            let inForce = meters.last { $0.x <= x } ?? meters[0]
            return (inForce.beats, inForce.unit)
        }
        var last: (beats: Int, unit: Int) { (meters[meters.count - 1].beats, meters[meters.count - 1].unit) }
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

        let meters = meterChanges(glyphs: glyphs, system: system, font: font,
                                  inherited: inheritedTime, consumed: &consumed)
        return Head(bottomDiatonic: bottomDiatonic,
                    keySignature: keySign * keyCount,
                    meters: meters,
                    consumed: consumed)
    }

    /// Digit glyphs are a time signature ONLY when they sit INSIDE the staff.
    ///
    /// The same codepoints carry measure numbers, multi-measure rest counts and
    /// tuplet numbers, which on PEAK mello.pdf outnumber the real time signature
    /// digits 35 to 8 and sit above or below the staff at step 11.10. Reading
    /// one of those as a meter makes every measure fail the sum check, which
    /// turns the validator from signal into noise.
    ///
    /// Inside the staff is enough on its own, so this scans the WHOLE staff and
    /// not just its head: measured over both charts, every in-staff digit is a
    /// real meter and there are only eight of them in 4 pages plus 1.
    private static func meterChanges(glyphs: [PlacedGlyph], system: StaffSystem,
                                     font: MusicFontTable,
                                     inherited: (beats: Int, unit: Int),
                                     consumed: inout Set<Int>) -> [(x: Double, beats: Int, unit: Int)] {
        var digits: [(index: Int, x: Double, step: Double, value: Int)] = []
        for (index, glyph) in glyphs.enumerated() {
            guard case .timeSigDigit(let value) = font.symbol(for: glyph.scalar) else { continue }
            let step = (glyph.y - system.bottomLineY) / system.halfSpace
            if step >= 0, step <= 8 { digits.append((index, glyph.x, step, value)) }
        }

        var changes: [(x: Double, beats: Int, unit: Int)] = [(-.greatestFiniteMagnitude,
                                                             inherited.beats, inherited.unit)]
        var used = Set<Int>()
        for lower in digits.sorted(by: { $0.x < $1.x }) {
            guard !used.contains(lower.index) else { continue }
            // The upper digit is the beats. Paired by a shared x: measured 0.00
            // apart in Opus and 0.65 in Leland.
            guard let upper = digits.first(where: {
                !used.contains($0.index) && $0.index != lower.index
                    && abs($0.x - lower.x) < timeSignaturePairReach && $0.step > lower.step + 1
            }) else { continue }
            used.insert(lower.index)
            used.insert(upper.index)
            consumed.insert(lower.index)
            consumed.insert(upper.index)
            changes.append((min(lower.x, upper.x), upper.value, lower.value))
        }
        if changes.count == 1 {
            Log.score.debug("[IMPORT] no time signature inside the staff at y \(system.bottomLineY, privacy: .public), carrying \(inherited.beats, privacy: .public)/\(inherited.unit, privacy: .public) forward")
        } else {
            Log.score.info("[IMPORT] \(changes.count - 1, privacy: .public) meter change(s) on the staff at y \(system.bottomLineY, privacy: .public)")
        }
        return changes.sorted { $0.x < $1.x }
    }

    // MARK: - Stage 3: notes

    private static func readNotes(glyphs: [PlacedGlyph], system: StaffSystem, head: Head,
                                  font: MusicFontTable, paths: [PlacedPath], barlines: [Double],
                                  measure: inout Int, onset: inout Double)
        -> (events: [ScoreEvent], voiceCount: Int, unreadable: [UInt32],
            meters: [Int: Double], units: [Int: Int]) {

        var events: [ScoreEvent] = []
        var unreadable: [UInt32] = []
        var voiceCount = 0
        /// What each measure this staff touches is supposed to hold, recorded as
        /// it goes because the meter can change part way along a staff.
        var meters: [Int: Double] = [:]
        var units: [Int: Int] = [:]
        /// Inline accidentals hold to the end of their measure, keyed by
        /// diatonic index so they apply to that letter in THAT octave, which is
        /// the actual notation rule.
        var active: [Int: Accidental] = [:]

        let stems = self.stems(in: paths, system: system)
        let beams = self.beams(in: paths, system: system)
        let rests = multiMeasureRests(in: paths, glyphs: glyphs, system: system, font: font)

        // Group noteheads by x. A shared x is a chord, and on a horn part that
        // is divisi, which is how the Florida chart is written throughout.
        var chords: [Double: [PlacedGlyph]] = [:]
        var singleRests: [(x: Double, value: NoteValue)] = []
        for (index, glyph) in glyphs.enumerated() {
            guard !head.consumed.contains(index) else { continue }
            let symbol = font.symbol(for: glyph.scalar)
            if case .unknown(let scalar) = symbol { unreadable.append(scalar) }
            if symbol.isNotehead {
                chords[(glyph.x * 10).rounded() / 10, default: []].append(glyph)
            } else if case .rest(let value) = symbol {
                singleRests.append((glyph.x, value.dotted(dots(after: glyph, among: glyphs,
                                                              system: system, font: font))))
            }
        }

        // One ordering over everything that occupies time, because a rest that
        // is not in the timeline is a note that starts too early.
        enum Item { case chord([PlacedGlyph]), rest(NoteValue), multiRest(bars: Int) }
        var timeline: [(x: Double, item: Item)] = []
        timeline += chords.map { ($0.key, Item.chord($0.value)) }
        timeline += singleRests.map { ($0.x, Item.rest($0.value)) }
        timeline += rests.map { ($0.centre, Item.multiRest(bars: $0.bars)) }
        timeline.sort { $0.x < $1.x }

        var barlineCursor = 0
        meters[measure] = Double(head.meter(at: -.greatestFiniteMagnitude).beats)
        units[measure] = head.meter(at: -.greatestFiniteMagnitude).unit
        for entry in timeline {
            while barlineCursor < barlines.count, barlines[barlineCursor] < entry.x {
                measure += 1
                active.removeAll()
                barlineCursor += 1
                meters[measure] = Double(head.meter(at: barlines[barlineCursor - 1]).beats)
                units[measure] = head.meter(at: barlines[barlineCursor - 1]).unit
            }
            let meter = head.meter(at: entry.x)
            let beatsPerMeasure = Double(meter.beats)
            meters[measure] = beatsPerMeasure
            units[measure] = meter.unit
            switch entry.item {
            case .multiRest(let bars):
                // Emitted one bar at a time rather than as a single long event,
                // so that Task 6 can check each of them and so the measure
                // numbers the user sees match the ones printed on the page.
                for bar in 0..<bars {
                    events.append(ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                                             onsetBeats: onset, durationBeats: beatsPerMeasure,
                                             measure: measure + bar, voice: 0))
                    meters[measure + bar] = beatsPerMeasure
                    units[measure + bar] = meter.unit
                    onset += beatsPerMeasure
                }
                measure += bars - 1

            case .rest(let value):
                let beats = value.beats(unit: meter.unit)
                events.append(ScoreEvent(note: nil, writtenName: "", outOfRangeName: nil,
                                         onsetBeats: onset, durationBeats: beats,
                                         measure: measure, voice: 0))
                onset += beats

            case .chord(let group):
                // Highest pitch is voice 0, and in this frame the highest pitch
                // is the LARGEST y.
                let heads = group.sorted { $0.y > $1.y }
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
                    let value = duration(of: glyph, among: glyphs, stems: stems, beams: beams,
                                         system: system, font: font)
                    let beats = value.beats(unit: meter.unit)
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
        }
        // Trailing barlines still end their measure, or the first event of the
        // next system lands in the one that just closed.
        while barlineCursor < barlines.count {
            measure += 1
            active.removeAll()
            barlineCursor += 1
            meters[measure] = Double(head.meter(at: barlines[barlineCursor - 1]).beats)
            units[measure] = head.meter(at: barlines[barlineCursor - 1]).unit
        }
        return (events, voiceCount, unreadable, meters, units)
    }

    // MARK: - Stage 4: how long does it last

    private struct Stem {
        let x: Double
        let minY: Double
        let maxY: Double
        /// The end away from the notehead, which is where flags and beams live.
        func tipY(from noteheadY: Double) -> Double {
            abs(maxY - noteheadY) > abs(minY - noteheadY) ? maxY : minY
        }
    }

    /// A notehead alone proves only a ceiling, so this is where the rest of the
    /// duration comes from: beams first, then flags, then dots.
    ///
    /// Beams and flags are mutually exclusive on a note, so beams are asked
    /// first and flags only answer when there are none. Counting both would
    /// make a beamed sixteenth into a sixty-fourth.
    private static func duration(of notehead: PlacedGlyph, among glyphs: [PlacedGlyph],
                                 stems: [Stem], beams: [PlacedPath],
                                 system: StaffSystem, font: MusicFontTable) -> NoteValue {
        var value = font.symbol(for: notehead.scalar).impliedValue ?? .quarter
        if value == .quarter {
            var halvings = beamCount(for: notehead, stems: stems, beams: beams, system: system)
            if halvings == 0 {
                halvings = flagCount(for: notehead, among: glyphs, system: system, font: font)
            }
            if halvings > 0 { value = NoteValue(1, 4 << min(halvings, 4)) }
        }
        return value.dotted(dots(after: notehead, among: glyphs, system: system, font: font))
    }

    /// Thin, tall, and NOT spanning the staff exactly, which is a barline.
    ///
    /// Both engravers stroke their stems, so `filled` is not a filter here for
    /// the same reason it is not one in StaffFitter. Measured lengths run 5.2 to
    /// 11.6 half-spaces.
    private static func stems(in paths: [PlacedPath], system: StaffSystem) -> [Stem] {
        paths.compactMap { path in
            let bounds = path.bounds
            guard Double(bounds.width) / system.halfSpace < stemMaxWidth,
                  Double(bounds.height) / system.halfSpace > stemMinLength else { return nil }
            let reach = barlineEndReach * system.halfSpace
            guard !(abs(Double(bounds.minY) - system.bottomLineY) <= reach
                    && abs(Double(bounds.maxY) - system.lineYs[4]) <= reach) else { return nil }
            return Stem(x: Double(bounds.midX), minY: Double(bounds.minY), maxY: Double(bounds.maxY))
        }
    }

    /// Short, thick, horizontal, and near a stem tip.
    ///
    /// Measured on both charts: 2.0 to 15 half-spaces wide and 0.6 to 2.6 thick.
    /// The width ceiling is what keeps a multi-measure rest's H-bar out, since
    /// that runs 20 to 66 half-spaces.
    private static func beams(in paths: [PlacedPath], system: StaffSystem) -> [PlacedPath] {
        paths.filter { path in
            let w = Double(path.bounds.width) / system.halfSpace
            let h = Double(path.bounds.height) / system.halfSpace
            return w >= beamMinWidth && w <= beamMaxWidth && h >= beamMinThickness && h <= beamMaxThickness
        }
    }

    /// The stem a notehead hangs on, found by CONTAINMENT rather than by
    /// matching an endpoint: a divisi chord shares one stem and its inner
    /// noteheads sit in the middle of it. Matching endpoints only found 68 of
    /// Florida's 110 stemmed noteheads; containment finds 108.
    private static func stem(for notehead: PlacedGlyph, stems: [Stem], system: StaffSystem) -> Stem? {
        stems.first { stem in
            let dx = (stem.x - notehead.x) / system.halfSpace
            return dx > -1.0 && dx < stemAttachReach
                && notehead.y >= stem.minY - system.halfSpace
                && notehead.y <= stem.maxY + system.halfSpace
        }
    }

    private static func beamCount(for notehead: PlacedGlyph, stems: [Stem],
                                  beams: [PlacedPath], system: StaffSystem) -> Int {
        guard let stem = stem(for: notehead, stems: stems, system: system) else { return 0 }
        let tip = stem.tipY(from: notehead.y)
        let slack = system.halfSpace
        return beams.filter { beam in
            Double(beam.bounds.minX) - slack <= stem.x
                && Double(beam.bounds.maxX) + slack >= stem.x
                && abs(Double(beam.bounds.midY) - tip) <= beamTipReach * system.halfSpace
        }.count
    }

    /// Measured placement: the down flag sits at the notehead's own x and 5
    /// half-spaces below it, the up flag 2.5 across and 5 above.
    private static func flagCount(for notehead: PlacedGlyph, among glyphs: [PlacedGlyph],
                                  system: StaffSystem, font: MusicFontTable) -> Int {
        for glyph in glyphs {
            guard case .flag(let count, _) = font.symbol(for: glyph.scalar) else { continue }
            let dx = (glyph.x - notehead.x) / system.halfSpace
            let dy = abs(glyph.y - notehead.y) / system.halfSpace
            if dx > -1.0, dx < stemAttachReach, dy >= flagMinOffset, dy <= flagMaxOffset { return count }
        }
        return 0
    }

    /// An augmentation dot sits to the RIGHT and follows the pitch: measured
    /// 3.3 half-spaces across in Leland and 4.1 in Opus, level with the note or
    /// one step up when the note is on a line. A staccato, which never moves
    /// right, is a different symbol and is ignored by the table.
    private static func dots(after glyph: PlacedGlyph, among glyphs: [PlacedGlyph],
                             system: StaffSystem, font: MusicFontTable) -> Int {
        glyphs.filter { candidate in
            guard font.symbol(for: candidate.scalar) == .augmentationDot else { return false }
            let dx = (candidate.x - glyph.x) / system.halfSpace
            let dy = (candidate.y - glyph.y) / system.halfSpace
            return dx >= dotMinOffset && dx <= dotMaxOffset && dy >= -0.6 && dy <= 1.6
        }.count
    }

    /// A multi-measure rest, and how many bars it stands for.
    ///
    /// This is the fix for measure numbers, not just for silence. Counting
    /// barlines alone treats an H-bar standing for six bars as one, so the
    /// reader ended Florida page 1 at measure 36 where the engraver prints 36 at
    /// the START of its last system, five bars short.
    ///
    /// The H-bar itself is stroked by MuseScore and filled by Sibelius, the same
    /// split as staff lines, so it is not the thing to key on. The END CAPS are:
    /// two short verticals spanning exactly steps 2 to 6 in both engravers.
    private static func multiMeasureRests(in paths: [PlacedPath], glyphs: [PlacedGlyph],
                                          system: StaffSystem, font: MusicFontTable)
        -> [(centre: Double, bars: Int)] {

        let capXs = paths.filter { path in
            let low = (Double(path.bounds.minY) - system.bottomLineY) / system.halfSpace
            let high = (Double(path.bounds.maxY) - system.bottomLineY) / system.halfSpace
            return Double(path.bounds.width) / system.halfSpace < stemMaxWidth
                && abs(low - 2) < endCapTolerance && abs(high - 6) < endCapTolerance
        }.map { Double($0.bounds.midX) }.sorted()

        var result: [(centre: Double, bars: Int)] = []
        var index = 0
        while index + 1 < capXs.count {
            let centre = (capXs[index] + capXs[index + 1]) / 2
            // The count is printed centred above the bar, in the MUSIC font. A
            // window this tight matters: PEAK's measure numbers sit at the same
            // height, and a wider one reads "4425424" instead of "4".
            let digits = glyphs.filter { glyph in
                guard case .timeSigDigit = font.symbol(for: glyph.scalar) else { return false }
                let step = (glyph.y - system.bottomLineY) / system.halfSpace
                return abs(glyph.x - centre) < countDigitReach * system.halfSpace
                    && step > 8 && step < 16
            }.sorted { $0.x < $1.x }.reduce(0) { total, glyph in
                if case .timeSigDigit(let value) = font.symbol(for: glyph.scalar) {
                    return total * 10 + value
                }
                return total
            }
            if digits > 0 {
                result.append((centre, digits))
            } else {
                // A bar with no readable count is still a bar of rest, and one
                // is the honest floor. Logged because a chart where this happens
                // often is a chart whose measure numbers will drift.
                Log.score.info("[IMPORT] multi-measure rest at x \(centre, privacy: .public) has no readable count, taking it as one bar")
                result.append((centre, 1))
            }
            index += 2
        }
        return result
    }

    // MARK: - Stage 5: the check that makes the reader trustworthy

    /// Measures whose durations do not sum to their time signature.
    ///
    /// Same idea as `verifyFingerings()` re-checking the fingering derivation in
    /// the browser on every load, and as `check-instruments.js` refusing to run
    /// when the stored table disagrees with the derivation. A measure that does
    /// not sum is a measure the reader got wrong. It is NOT repaired here: the
    /// events keep whatever was read and the UI shows the bar flagged, because
    /// issue #9 is the precedent that a wrong value taught confidently is worse
    /// than an admitted gap.
    ///
    /// **Only the top voice is summed.** Three rules were tried against the
    /// divisi chart in #19. Summing every voice and flagging any disagreement,
    /// which is what this task was first written to do, flags two extra bars,
    /// because an engraver writes ONE notehead where a divisi goes briefly to
    /// unison and the lower voice is then legitimately short. Summing the
    /// longest duration at each onset flags five extra, because it double counts
    /// wherever the lower voice holds through two notes of the upper. The top
    /// voice alone agrees with the page on 39 of 41 bars, and a validator that
    /// cries wolf is worse than none: see the note on time signature digits.
    private static func suspectMeasures(in events: [ScoreEvent],
                                        meters: [Int: Double]) -> Set<Int> {
        var sums: [Int: Double] = [:]
        for event in events where event.voice == 0 {
            sums[event.measure, default: 0] += event.durationBeats
        }
        guard let first = sums.keys.min(), let last = sums.keys.max() else { return [] }

        var suspect: Set<Int> = []
        for (bar, sum) in sums {
            guard let expected = meters[bar] else { continue }
            guard abs(sum - expected) > sumTolerance else { continue }
            // A short first or last bar is a pickup or the tail of one, which is
            // how music is written and not a reading error. Overfull is still
            // wrong at either end.
            if (bar == first || bar == last) && sum < expected { continue }
            suspect.insert(bar)
            Log.score.info("[IMPORT] measure \(bar, privacy: .public) holds \(sum, privacy: .public) beats against \(expected, privacy: .public), flagged")
        }
        if !suspect.isEmpty {
            Log.score.error("[IMPORT] \(suspect.count, privacy: .public) of \(sums.count, privacy: .public) measures did not sum to their time signature")
            #if DEBUG
            FileLog.write("[IMPORT] \(suspect.count) of \(sums.count) measures did not sum")
            #endif
        }
        return suspect
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
