// GENERATED FILE. Do not edit by hand.
//
// Produced by ios/scripts/sync-note-data.py from index.html, which is the
// source of truth for the note and scale data in BOTH products. To correct a
// frequency or a fingering, edit index.html and re-run:
//
//     python3 ios/scripts/sync-note-data.py
//
// Run it with --check to prove the two are still in sync.

import Foundation

extension Note {
    /// Every note the app knows about, including both spellings of each
    /// enharmonic pair, because the two spellings sit on different lines of
    /// the staff and the drill accepts either as an answer.
    static let all: [Note] = [
        Note(name: "E1",  frequency: 41.20,    staffPosition: 330,  fingering: "",      accidental: .natural),
        Note(name: "F1",  frequency: 43.65,    staffPosition: 320,  fingering: "",      accidental: .natural),
        Note(name: "F#1", frequency: 46.25,    staffPosition: 320,  fingering: "",      accidental: .sharp),
        Note(name: "Gb1", frequency: 46.25,    staffPosition: 310,  fingering: "",      accidental: .flat),
        Note(name: "G1",  frequency: 49.00,    staffPosition: 310,  fingering: "",      accidental: .natural),
        Note(name: "Ab1", frequency: 51.91,    staffPosition: 300,  fingering: "",      accidental: .flat),
        Note(name: "A1",  frequency: 55.00,    staffPosition: 300,  fingering: "",      accidental: .natural),
        Note(name: "Bb1", frequency: 58.27,    staffPosition: 290,  fingering: "",      accidental: .flat),
        Note(name: "B1",  frequency: 61.74,    staffPosition: 290,  fingering: "",      accidental: .natural),
        Note(name: "C2",  frequency: 65.41,    staffPosition: 280,  fingering: "",      accidental: .natural),
        Note(name: "C#2", frequency: 69.30,    staffPosition: 280,  fingering: "",      accidental: .sharp),
        Note(name: "Db2", frequency: 69.30,    staffPosition: 270,  fingering: "",      accidental: .flat),
        Note(name: "D2",  frequency: 73.42,    staffPosition: 270,  fingering: "",      accidental: .natural),
        Note(name: "Eb2", frequency: 77.78,    staffPosition: 260,  fingering: "",      accidental: .flat),
        Note(name: "E2",  frequency: 82.41,    staffPosition: 260,  fingering: "",      accidental: .natural),
        Note(name: "F2",  frequency: 87.31,    staffPosition: 250,  fingering: "",      accidental: .natural),
        Note(name: "F#2", frequency: 92.50,    staffPosition: 250,  fingering: "",      accidental: .sharp),
        Note(name: "Gb2", frequency: 92.50,    staffPosition: 240,  fingering: "",      accidental: .flat),
        Note(name: "G2",  frequency: 98.00,    staffPosition: 240,  fingering: "",      accidental: .natural),
        Note(name: "Ab2", frequency: 103.83,   staffPosition: 230,  fingering: "",      accidental: .flat),
        Note(name: "A2",  frequency: 110.00,   staffPosition: 230,  fingering: "",      accidental: .natural),
        Note(name: "Bb2", frequency: 116.54,   staffPosition: 220,  fingering: "",      accidental: .flat),
        Note(name: "B2",  frequency: 123.47,   staffPosition: 220,  fingering: "",      accidental: .natural),
        Note(name: "C3",  frequency: 130.81,   staffPosition: 210,  fingering: "",      accidental: .natural),
        Note(name: "C#3", frequency: 138.59,   staffPosition: 210,  fingering: "",      accidental: .sharp),
        Note(name: "Db3", frequency: 138.59,   staffPosition: 200,  fingering: "",      accidental: .flat),
        Note(name: "D3",  frequency: 146.83,   staffPosition: 200,  fingering: "",      accidental: .natural),
        Note(name: "Eb3", frequency: 155.56,   staffPosition: 190,  fingering: "",      accidental: .flat),
        Note(name: "E3",  frequency: 164.81,   staffPosition: 190,  fingering: "",      accidental: .natural),
        Note(name: "F3",  frequency: 174.61,   staffPosition: 180,  fingering: "",      accidental: .natural),
        Note(name: "F#3", frequency: 185.00,   staffPosition: 180,  fingering: "1+2+3", accidental: .sharp),
        Note(name: "Gb3", frequency: 185.00,   staffPosition: 170,  fingering: "1+2+3", accidental: .flat),
        Note(name: "G3",  frequency: 196.00,   staffPosition: 170,  fingering: "1+3",   accidental: .natural),
        Note(name: "Ab3", frequency: 207.65,   staffPosition: 160,  fingering: "2+3",   accidental: .flat),
        Note(name: "A3",  frequency: 220.00,   staffPosition: 160,  fingering: "1+2",   accidental: .natural),
        Note(name: "Bb3", frequency: 233.08,   staffPosition: 150,  fingering: "1",     accidental: .flat),
        Note(name: "B3",  frequency: 246.94,   staffPosition: 150,  fingering: "2",     accidental: .natural),
        Note(name: "C4",  frequency: 261.63,   staffPosition: 140,  fingering: "Open",  accidental: .natural),
        Note(name: "C#4", frequency: 277.18,   staffPosition: 140,  fingering: "1+2+3", accidental: .sharp),
        Note(name: "Db4", frequency: 277.18,   staffPosition: 130,  fingering: "1+2+3", accidental: .flat),
        Note(name: "D4",  frequency: 293.66,   staffPosition: 130,  fingering: "1+3",   accidental: .natural),
        Note(name: "Eb4", frequency: 311.13,   staffPosition: 120,  fingering: "2+3",   accidental: .flat),
        Note(name: "E4",  frequency: 329.63,   staffPosition: 120,  fingering: "1+2",   accidental: .natural),
        Note(name: "F4",  frequency: 349.23,   staffPosition: 110,  fingering: "1",     accidental: .natural),
        Note(name: "F#4", frequency: 369.99,   staffPosition: 110,  fingering: "2",     accidental: .sharp),
        Note(name: "Gb4", frequency: 369.99,   staffPosition: 100,  fingering: "2",     accidental: .flat),
        Note(name: "G4",  frequency: 392.00,   staffPosition: 100,  fingering: "Open",  accidental: .natural),
        Note(name: "Ab4", frequency: 415.30,   staffPosition: 90,   fingering: "2+3",   accidental: .flat),
        Note(name: "A4",  frequency: 440.00,   staffPosition: 90,   fingering: "1+2",   accidental: .natural),
        Note(name: "Bb4", frequency: 466.16,   staffPosition: 80,   fingering: "1",     accidental: .flat),
        Note(name: "B4",  frequency: 493.88,   staffPosition: 80,   fingering: "2",     accidental: .natural),
        Note(name: "C5",  frequency: 523.25,   staffPosition: 70,   fingering: "Open",  accidental: .natural),
        Note(name: "C#5", frequency: 554.37,   staffPosition: 70,   fingering: "1+2",   accidental: .sharp),
        Note(name: "Db5", frequency: 554.37,   staffPosition: 60,   fingering: "1+2",   accidental: .flat),
        Note(name: "D5",  frequency: 587.33,   staffPosition: 60,   fingering: "1",     accidental: .natural),
        Note(name: "Eb5", frequency: 622.25,   staffPosition: 50,   fingering: "2",     accidental: .flat),
        Note(name: "E5",  frequency: 659.26,   staffPosition: 50,   fingering: "Open",  accidental: .natural),
        Note(name: "F5",  frequency: 698.46,   staffPosition: 40,   fingering: "1",     accidental: .natural),
        Note(name: "F#5", frequency: 739.99,   staffPosition: 40,   fingering: "2",     accidental: .sharp),
        Note(name: "Gb5", frequency: 739.99,   staffPosition: 30,   fingering: "2",     accidental: .flat),
        Note(name: "G5",  frequency: 783.99,   staffPosition: 30,   fingering: "Open",  accidental: .natural),
        Note(name: "Ab5", frequency: 830.61,   staffPosition: 20,   fingering: "2+3",   accidental: .flat),
        Note(name: "A5",  frequency: 880.00,   staffPosition: 20,   fingering: "1+2",   accidental: .natural),
        Note(name: "Bb5", frequency: 932.33,   staffPosition: 10,   fingering: "1",     accidental: .flat),
        Note(name: "B5",  frequency: 987.77,   staffPosition: 10,   fingering: "2",     accidental: .natural),
        Note(name: "C6",  frequency: 1046.50,  staffPosition: 0,    fingering: "Open",  accidental: .natural),
    ]
}

extension Scale {
    /// The scales and exercises from the web version, in its order.
    ///
    /// Names carry both the concert and the written pitch because the
    /// mellophone is in F and a director calls the concert key out loud while
    /// the player reads the written one.
    ///
    /// `detail` is the plain-English half. The names are the words a director
    /// says, so they stay; the description is what makes them mean something to
    /// someone who has not heard them before.
    static let all: [Scale] = [
        Scale(
            name: "Concert Bb (Written F)",
            shownName: nil,
            detail: String(localized: "The first scale every band learns. If you get only one solid before the season starts, make it this one."),
            heldFingering: nil,
            noteNames: ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5"]
        ),
        Scale(
            name: "Concert Eb (Written Bb)",
            shownName: nil,
            detail: String(localized: "The other one you get asked for constantly. Warm up with it until the fingerings stop needing thought."),
            heldFingering: nil,
            noteNames: ["Bb3", "C4", "D4", "Eb4", "F4", "G4", "A4", "Bb4"]
        ),
        Scale(
            name: "Concert F (Written C)",
            shownName: nil,
            detail: String(localized: "No sharps or flats in your part, so you can listen to your sound instead of thinking about your fingers."),
            heldFingering: nil,
            noteNames: ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
        ),
        Scale(
            name: "Concert Ab (Written Eb)",
            shownName: nil,
            detail: String(localized: "Marching shows live in the flat keys and this is the one that catches people out. Know it cold."),
            heldFingering: nil,
            noteNames: ["Eb4", "F4", "G4", "Ab4", "Bb4", "C5", "D5", "Eb5"]
        ),
        Scale(
            name: "Chromatic (1 octave)",
            shownName: String(localized: "Chromatic (1 octave)"),
            detail: String(localized: "Every note in order, no skipping. The fastest way to nail down a fingering you keep missing."),
            heldFingering: nil,
            noteNames: ["C4", "C#4", "D4", "Eb4", "E4", "F4", "F#4", "G4", "Ab4", "A4", "Bb4", "B4", "C5"]
        ),
        Scale(
            name: "Lip Slurs (Open)",
            shownName: String(localized: "Lip Slurs (Open)"),
            detail: String(localized: "Same fingering the whole way, so your lips do all the work of changing notes. This is how you build a high range."),
            heldFingering: "Open",
            noteNames: ["C4", "G4", "C5", "E5", "G5", "E5", "C5", "G4", "C4"]
        ),
        Scale(
            name: "Lip Slurs (1st Valve)",
            shownName: String(localized: "Lip Slurs (1st Valve)"),
            detail: String(localized: "The same lip work with the first valve held down the whole time. Do not move your fingers."),
            heldFingering: "1",
            noteNames: ["Bb3", "F4", "Bb4", "D5", "F5", "D5", "Bb4", "F4", "Bb3"]
        ),
        Scale(
            name: "Lip Slurs (1+2)",
            shownName: String(localized: "Lip Slurs (1+2)"),
            detail: String(localized: "Lip slurs again, holding 1 and 2 down. Slower is harder, and slower is the point."),
            heldFingering: "1+2",
            noteNames: ["A3", "E4", "A4", "C#5", "E5", "C#5", "A4", "E4", "A3"]
        ),
        Scale(
            name: "Long Tones (low)",
            shownName: String(localized: "Long Tones (low)"),
            detail: String(localized: "Hold each note as long as you can, steady and in tune. It is boring, and it is the thing that makes a section sound good."),
            heldFingering: nil,
            noteNames: ["G3", "A3", "Bb3", "C4", "D4", "E4", "F4", "G4"]
        ),
        Scale(
            name: "Long Tones (mid)",
            shownName: String(localized: "Long Tones (mid)"),
            detail: String(localized: "The same holding work in the middle of your range, where most of your music actually sits."),
            heldFingering: nil,
            noteNames: ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5"]
        ),
    ]
}
