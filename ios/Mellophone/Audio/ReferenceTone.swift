import Foundation

/// Whatever plays the note check's "Hear it".
///
/// The check screen is opened from two places now, a chart and the tuner
/// (#32), and each already owns something that makes a sound: the chart its
/// `PartPlayer`, the Trainer its `TonePlayer`. The screen borrows that one
/// and does not make a third. A player is a node on the engine the whole app
/// shares and it stays attached for good (see `PartPlayer`), so a player made
/// per sheet would leave one behind every time the sheet opened.
protocol ReferenceTone: AnyObject {
    /// One note at exactly `frequency`, which is a SOUNDING pitch and can be
    /// an octave under anything else the app plays. Dry, and with the filter
    /// held open so a phone speaker has something to make of it.
    func reference(frequency: Double, duration: Double, volume: Double)
    func stop()
}

extension PartPlayer: ReferenceTone {
    func reference(frequency: Double, duration: Double, volume: Double) {
        // Dry, whatever the chart is set to. A hall rings for two seconds
        // after the note, on the note, into a microphone next to the speaker,
        // and the screen would tick the student off for a sound the phone
        // made. The chart puts its own room back the next time it plays.
        room = .dry
        sound(frequency: frequency, duration: duration, volume: volume,
              brightnessFloor: NoteCheck.referenceBrightnessFloor)
    }
}

extension TonePlayer: ReferenceTone {
    func reference(frequency: Double, duration: Double, volume: Double) {
        self.volume = volume
        play(frequency: frequency, duration: duration, brightnessFloor: NoteCheck.referenceBrightnessFloor)
    }
}
