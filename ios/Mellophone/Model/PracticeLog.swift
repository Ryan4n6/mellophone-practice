import Foundation
import OSLog

/// One saved practice session.
struct PracticeSession: Codable, Identifiable, Hashable {
    let date: Date
    let seconds: Int

    var id: String { "\(date.timeIntervalSince1970)-\(seconds)" }
}

/// The practice log. On the device, and nowhere else.
///
/// There is no account, no sync and no backend to send this to. See
/// PrivacyInfo.xcprivacy and issue #2: the people using this are likely to
/// include minors, so the answer to every collection question is none.
final class PracticeLog: ObservableObject {
    @Published private(set) var sessions: [PracticeSession] = []

    /// Matches the web version's cap. Newest first, oldest dropped.
    static let maxEntries = 50
    /// Matches `saveSession` in the web version, which silently ignores anything
    /// shorter. Stops a stray tap on Start and Save from filling the log with
    /// two-second entries.
    static let minimumSeconds = 10

    private let key = "mello-practice-log"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var totalSeconds: Int { sessions.reduce(0) { $0 + $1.seconds } }

    /// Returns false when the session was too short to record, so the UI can say
    /// so rather than appearing to do nothing.
    @discardableResult
    func save(seconds: Int, on date: Date = Date()) -> Bool {
        guard seconds >= Self.minimumSeconds else {
            Log.store.info("[STORE] session of \(seconds, privacy: .public)s ignored, under the \(Self.minimumSeconds, privacy: .public)s floor")
            return false
        }
        sessions.insert(PracticeSession(date: date, seconds: seconds), at: 0)
        if sessions.count > Self.maxEntries {
            sessions.removeLast(sessions.count - Self.maxEntries)
        }
        persist()
        Log.store.info("[STORE] saved \(seconds, privacy: .public)s, \(self.sessions.count, privacy: .public) sessions held")
        return true
    }

    func clear() {
        sessions = []
        defaults.removeObject(forKey: key)
        Log.store.info("[STORE] log cleared")
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        do {
            sessions = try JSONDecoder().decode([PracticeSession].self, from: data)
            Log.store.info("[STORE] loaded \(self.sessions.count, privacy: .public) sessions")
        } catch {
            // A log that cannot be read is not worth crashing or clearing over.
            // Leave the stored data alone so a future build could still recover
            // it, and start empty for now.
            Log.store.error("[STORE] could not decode the practice log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(sessions), forKey: key)
        } catch {
            Log.store.error("[STORE] could not save the practice log: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// mm:ss, matching the web version's `formatTime`, extended to hours so a long
/// total does not read as an absurd minute count.
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%02d:%02d", minutes, secs)
}
