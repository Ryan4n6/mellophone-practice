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

#if DEBUG
/// Appends diagnostic lines to a file inside the app container.
///
/// This exists because `devicectl --console` CANNOT be used to diagnose a
/// background-suspension bug: an attached process is held alive by the debugger,
/// so the very thing being measured is changed by measuring it. The phase 1
/// locked-screen evidence in issue #3 was gathered that way and is therefore
/// suspect.
///
/// A file the app writes itself has no such problem. Launch from the home
/// screen, reproduce, then pull it:
///
///     xcrun devicectl device info files --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier com.massfeller.mellophone --username mobile
///     xcrun devicectl device copy from --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier com.massfeller.mellophone \
///       --source Documents/diagnostic.log --destination ./diagnostic.log
enum FileLog {
    private static let queue = DispatchQueue(label: "com.massfeller.mellophone.filelog")

    static var url: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("diagnostic.log")
    }

    static func write(_ line: String) {
        guard let url else { return }
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        queue.async {
            guard let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Called at launch so each run starts a fresh file rather than accumulating
    /// every session's lines into one unreadable blob.
    static func startNewRun() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
        write("=== run started ===")
    }
}
#endif
