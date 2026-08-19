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
            detail: "The first scale every band learns. Your director calls it concert Bb; on your horn you play it in F.",
            noteNames: ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5"]
        ),
        Scale(
            name: "Concert Eb (Written Bb)",
            detail: "The other one you get asked for constantly. Concert Eb to the band, written Bb to you.",
            noteNames: ["Bb3", "C4", "D4", "Eb4", "F4", "G4", "A4", "Bb4"]
        ),
        Scale(
            name: "Concert F (Written C)",
            detail: "No sharps or flats in your part, so you can listen to your sound instead of thinking about your fingers.",
            noteNames: ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
        ),
        Scale(
            name: "Concert Ab (Written Eb)",
            detail: "Four flats for the band, three for you. Marching shows live in these keys, so know it cold.",
            noteNames: ["Eb4", "F4", "G4", "Ab4", "Bb4", "C5", "D5", "Eb5"]
        ),
        Scale(
            name: "Chromatic (1 octave)",
            detail: "Every note in order, no skipping. The fastest way to nail down a fingering you keep missing.",
            noteNames: ["C4", "C#4", "D4", "Eb4", "E4", "F4", "F#4", "G4", "Ab4", "A4", "Bb4", "B4", "C5"]
        ),
        Scale(
            name: "Lip Slurs (Open)",
            detail: "Same fingering the whole way, so your lips do all the work of changing notes. This is how you build a high range.",
            noteNames: ["C4", "G4", "C5", "E5", "G5", "E5", "C5", "G4", "C4"]
        ),
        Scale(
            name: "Lip Slurs (1st Valve)",
            detail: "The same lip work with the first valve held down the whole time. Do not move your fingers.",
            noteNames: ["Bb3", "F4", "Bb4", "D5", "F5", "D5", "Bb4", "F4", "Bb3"]
        ),
        Scale(
            name: "Lip Slurs (1+2)",
            detail: "Lip slurs again, holding 1 and 2 down. Slower is harder, and slower is the point.",
            noteNames: ["A3", "E4", "A4", "C#5", "E5", "C#5", "A4", "E4", "A3"]
        ),
        Scale(
            name: "Long Tones (low)",
            detail: "Hold each note as long as you can, steady and in tune. It is boring, and it is the thing that makes a section sound good.",
            noteNames: ["G3", "A3", "Bb3", "C4", "D4", "E4", "F4", "G4"]
        ),
        Scale(
            name: "Long Tones (mid)",
            detail: "The same holding work in the middle of your range, where most of your music actually sits.",
            noteNames: ["F4", "G4", "A4", "Bb4", "C5", "D5", "E5", "F5"]
        ),
    ]
}
