import XCTest
@testable import Mellophone

/// Spanish and French (#67), and the jumps the page prints that are not
/// played (#64).
///
/// The note names are data everywhere but the screen, so most of this is the
/// one rule that turns "Bb4" into what a student reads. The octave numbers
/// were measured, not assumed: Spanish in the Americas counts middle C as
/// Do4 (the scientific index), French as Do3 (the Franco-Belgian index).
final class LanguageTests: XCTestCase {

    // MARK: - Note names

    func testLettersAreTheStoredNames() {
        for name in ["C4", "Bb4", "F#3", "C6"] { XCTAssertEqual(NoteNaming.letters.show(name), name) }
    }

    func testSpanishSolfegeCountsMiddleCAsDo4() {
        XCTAssertEqual(NoteNaming.solfege.show("C4"), "Do4")
        XCTAssertEqual(NoteNaming.solfege.show("Bb4"), "Si\u{266D}4")
        XCTAssertEqual(NoteNaming.solfege.show("F#3"), "Fa\u{266F}3")
        XCTAssertEqual(NoteNaming.solfege.show("D5"), "Re5")
        XCTAssertEqual(NoteNaming.solfege.show("G5"), "Sol5")
    }

    func testFrenchSolfegeCountsMiddleCAsDo3() {
        XCTAssertEqual(NoteNaming.solfegeFrench.show("C4"), "Do3")
        XCTAssertEqual(NoteNaming.solfegeFrench.show("C5"), "Do4")
        XCTAssertEqual(NoteNaming.solfegeFrench.show("D5"), "R\u{E9}4")
        XCTAssertEqual(NoteNaming.solfegeFrench.show("Bb3"), "Si\u{266D}2")
        XCTAssertEqual(NoteNaming.solfegeFrench.show("F#3"), "Fa\u{266F}2")
    }

    /// A key is a pitch class with no octave, and a fingering or a blank is
    /// not a note at all.
    func testKeysAndThingsThatAreNotNotes() {
        XCTAssertEqual(NoteNaming.solfege.showKey("Bb"), "Si\u{266D}")
        XCTAssertEqual(NoteNaming.solfegeFrench.showKey("Eb"), "Mi\u{266D}")
        for other in ["Open", "1+2", "?", " ", ""] { XCTAssertEqual(NoteNaming.solfege.show(other), other) }
    }

    /// Every one of the 36 rows reads back as a different name in every
    /// naming: two spellings of one pitch stay two names, as on the staff.
    func testNoTwoNotesShareAShownName() {
        for naming in NoteNaming.allCases {
            let shown = Note.all.map { naming.show($0.name) }
            XCTAssertEqual(Set(shown).count, Note.all.count, "\(naming)")
        }
    }

    func testANewInstallFollowsTheLanguage() {
        XCTAssertEqual(NoteNaming.default(forLanguage: "es"), .solfege)
        XCTAssertEqual(NoteNaming.default(forLanguage: "fr"), .solfegeFrench)
        XCTAssertEqual(NoteNaming.default(forLanguage: "en"), .letters)
        XCTAssertEqual(NoteNaming.default(forLanguage: "de"), .letters, "a language the app does not speak shows English")
        XCTAssertEqual(NoteNaming.default(forLanguage: nil), .letters)
    }

    /// What the note check says, in the student's naming.
    func testTheNoteCheckNamesNotesTheWayTheStudentReads() {
        let c5 = NoteCheck(writtenName: "C5", writtenFrequency: 523.25, instrument: .mellophone)
        let wrong = NoteCheck.Verdict.wrongNote(writtenName: "G4", sameValves: true, tooHigh: false)
        XCTAssertEqual(c5.words(for: wrong, confirmed: false, naming: .solfegeFrench).headline, "That's Sol3")
        XCTAssertEqual(c5.words(for: .inTune(cents: 2), confirmed: true, naming: .solfege).detail, "Do5, Open")
    }

    func testAKeyIsNamedFromItsParts() {
        let scale = Scale.all.first { $0.name == "Concert Bb (Written F)" }
        XCTAssertEqual(scale?.displayName(for: .trumpet, naming: .solfege), "Concert Mi\u{266D} (Written Fa)")
        XCTAssertEqual(scale?.displayName(for: .mellophone, naming: .letters), "Concert Bb (Written F)")
    }

    // MARK: - The catalog

    private func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Mellophone/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    /// The format arguments of a string, by position, so a translation that
    /// reorders them with %2$@ still matches.
    private func arguments(_ text: String) -> [String] {
        let matches = text.matches(of: /%(?:(\d+)\$)?(@|lld)/)
        let positional = matches.compactMap { $0.1.flatMap { Int($0) } }
        if positional.count == matches.count, !positional.isEmpty {
            return zip(positional, matches).sorted { $0.0 < $1.0 }.map { String($0.1.2) }
        }
        return matches.map { String($0.2) }
    }

    /// Every key is in both languages, and no translation drops, adds or
    /// changes the type of an argument: a missing %lld shows a student "%lld".
    func testEveryKeyIsTranslatedWithTheSameArguments() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 250)
        var problems: [String] = []
        for (key, value) in strings {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in ["es", "fr"] {
                guard let entry = localizations[language] as? [String: Any] else { problems.append("\(language) missing: \(key)"); continue }
                var texts: [String] = []
                if let unit = entry["stringUnit"] as? [String: Any], let text = unit["value"] as? String { texts.append(text) }
                if let plural = (entry["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    texts += plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
                }
                if texts.isEmpty { problems.append("\(language) empty: \(key)") }
                for text in texts where arguments(text) != arguments(key) {
                    problems.append("\(language) arguments differ: \(key) -> \(text)")
                }
                for text in texts where text.contains("\u{2014}") || text.contains("\u{2013}") {
                    problems.append("\(language) has a dash: \(text)")
                }
            }
        }
        XCTAssertEqual(problems, [])
    }

    /// The compiled bundle answers in Spanish and French, plurals included:
    /// what the catalog says is what a phone set to the language reads.
    func testThePhoneReadsTheTranslations() throws {
        func bundle(_ language: String) throws -> Bundle {
            try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)), "\(language).lproj")
        }
        let es = try bundle("es"), fr = try bundle("fr")
        XCTAssertEqual(es.localizedString(forKey: "Open", value: nil, table: nil), "Al aire")
        XCTAssertEqual(fr.localizedString(forKey: "Open", value: nil, table: nil), "\u{C0} vide")
        let low = { (b: Bundle, n: Int) in
            String.localizedStringWithFormat(b.localizedString(forKey: "%lld cents low", value: nil, table: nil), n)
        }
        XCTAssertEqual(low(es, 1), "1 cent por debajo")
        XCTAssertEqual(low(es, 12), "12 cents por debajo")
        XCTAssertEqual(low(fr, 12), "12 cents trop bas")
        let mic = try XCTUnwrap(es.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist"))
        XCTAssertTrue(mic.contains("No se graba nada"), mic)
    }

    // MARK: - Jumps not taken (#64)

    @MainActor
    private func model(_ repeats: Repeats) -> PartModel {
        let events = (1...6).map {
            ScoreEvent(note: Note.named("C5"), writtenName: "C5", outOfRangeName: nil,
                       onsetBeats: Double($0 - 1) * 4, durationBeats: 4, measure: $0, voice: 0)
        }
        let model = PartModel()
        model.adopt(Score(events: events, timeSignature: (4, 4), keySignature: 0, voiceCount: 1,
                          suspectMeasures: [], unreadableSymbols: [], repeats: repeats))
        return model
    }

    @MainActor
    func testADSWithNoSignIsSaidOnTheScreen() {
        var repeats = Repeats()
        repeats.jumps = [4: JumpSign(back: .dalSegno, until: .end)]
        let notes = model(repeats).jumpsNotTaken
        XCTAssertEqual(notes, ["The D.S. in bar 4 is not played: no sign was found on the page to go back to. Take it from the page."])
    }

    @MainActor
    func testAToCodaWithNoCodaAfterItIsSaid() {
        var repeats = Repeats()
        repeats.segno = 1
        repeats.toCoda = 3
        repeats.jumps = [5: JumpSign(back: .dalSegno, until: .coda)]
        XCTAssertEqual(model(repeats).jumpsNotTaken,
                       ["The To Coda in bar 3 is not played: no coda was found after it. Take it from the page."])
    }

    @MainActor
    func testJumpsThatArePlayedSayNothing() {
        var repeats = Repeats()
        repeats.segno = 2
        repeats.toCoda = 3
        repeats.coda = 5
        repeats.jumps = [4: JumpSign(back: .dalSegno, until: .coda)]
        let model = model(repeats)
        XCTAssertEqual(model.jumpsNotTaken, [])
        XCTAssertEqual(model.jumpTaken, "D.S. al Coda", "the card footer names it")
    }
}
