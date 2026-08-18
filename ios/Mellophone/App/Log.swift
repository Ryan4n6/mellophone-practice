import OSLog

/// Unified logging for the app.
///
/// Every category writes with a bracketed, greppable prefix in the message
/// itself (`[METRO]`, `[AUDIO]`, ...) as well as the os.Logger category, because
/// the two are searched differently: Console.app filters on category, but a
/// `xcrun devicectl` / `log stream` dump on a build mac is grepped as plain
/// text. Both paths matter when the bug only reproduces on a locked phone in a
/// band room and all you get back is a log capture.
enum Log {
    private static let subsystem = "com.massfeller.mellophone"

    /// AVAudioSession lifecycle: category, activation, interruptions, routes.
    static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Metronome scheduling and the audio clock. The timing-critical path.
    static let metro = Logger(subsystem: subsystem, category: "metronome")
    /// Haptics engine lifecycle and per-beat firing.
    static let haptics = Logger(subsystem: subsystem, category: "haptics")
    /// Tone synthesis for the trainer and scales.
    static let tone = Logger(subsystem: subsystem, category: "tone")
    /// Persistence: practice log, range, preferences.
    static let store = Logger(subsystem: subsystem, category: "store")
}
