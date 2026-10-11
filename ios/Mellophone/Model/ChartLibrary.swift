import Foundation
import OSLog

/// One PDF the student has brought in.
struct Chart: Identifiable, Hashable {
    let url: URL

    var id: String { url.lastPathComponent }
    /// The file's own name, which is what the director called it and what the
    /// student will look for.
    var title: String { url.deletingPathExtension().lastPathComponent }
}

/// The one chart the app ships (#28).
///
/// Reading a chart is the centre of the app and a new install has none: the
/// director has not sent the parts yet, or sent paper. So the first run puts
/// one short piece of our own in the library, to open and hear before any
/// file has been found.
///
/// It is OURS, sixteen bars written for this app, with its MusicXML source in
/// `ios/scripts/sample-chart.musicxml`. That is the only kind of music that
/// may go in the bundle: Sam's charts are copyrighted arrangements, and the
/// App Store record says the app uses no third party content.
enum SampleChart {
    /// The file's name is its title in the list, so it says what it is.
    static let name = "Sample Chart - Band Room March"
    static var url: URL? { Bundle.main.url(forResource: name, withExtension: "pdf") }
    /// Set once the sample has been put in the library. It is what makes
    /// removing the sample stick.
    static let seededKey = "mello-sample-chart-seeded"
}

/// The charts kept on this device. On the device, and nowhere else.
///
/// A chart is COPIED in when it is opened. The file picker hands back a
/// security-scoped address inside OneDrive that stops working when the app
/// next launches, and a part a student is learning gets opened every day for
/// weeks. Without a copy that is a trip through the picker and a download each
/// time, and no music at all on a bus with no signal, which is where this app
/// is supposed to work.
///
/// One file here can be the app's own: the sample chart, copied in on the first
/// run (see `SampleChart`). Every other file was put there by the person
/// holding the phone, and the sample is theirs to remove like any of them.
final class ChartLibrary: ObservableObject {
    @Published private(set) var charts: [Chart] = []

    private let directory: URL
    private let files = FileManager.default

    /// `directory` is a parameter so a test can point this at a scratch folder
    /// rather than at the charts of whoever is running the tests.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        reload()
    }

    /// The library the app uses, with the sample chart in it on a first run.
    ///
    /// A factory and not something `init` does, so a test that builds a
    /// library in a scratch folder gets an empty one.
    static func withSample() -> ChartLibrary {
        let library = ChartLibrary()
        library.seedSample(from: SampleChart.url)
        return library
    }

    /// Put the sample chart in, ONCE per install.
    ///
    /// Once, because it is the user's library. A student who removes the
    /// sample has said they do not want it, and a chart that comes back every
    /// launch is clutter they cannot get rid of. The flag is only set after a
    /// copy that worked, so a failed first run tries again on the next.
    func seedSample(from sample: URL?, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: SampleChart.seededKey) else { return }
        guard let sample else {
            Log.store.error("[CHARTS] the sample chart is not in the bundle, nothing seeded")
            return
        }
        do {
            try add(from: sample)
            defaults.set(true, forKey: SampleChart.seededKey)
            Log.store.info("[CHARTS] seeded the sample chart")
        } catch {
            Log.store.error("[CHARTS] could not seed the sample chart: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Application Support and not Documents: this app does not share its
    /// Documents folder, and a copy the student cannot see in Files should not
    /// sit somewhere that implies they can.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Charts", isDirectory: true)
    }

    /// Copy a picked file in and return where it now lives.
    ///
    /// Bringing in a file with a name already here REPLACES it. A director who
    /// fixes a wrong note re-exports under the same name, and keeping the old
    /// one beside it as "Show Opener 2" leaves the student guessing which is
    /// current.
    @discardableResult
    func add(from source: URL) throws -> Chart {
        // OneDrive hands back a file that may not be on the phone yet. The
        // scoped access is what permits the read and the coordinator is what
        // makes the provider go and fetch it; a plain copy can succeed on a
        // placeholder and store nothing useful.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { resolved in
            do {
                // Same file, already in the library: nothing to copy, and
                // removing it first would delete the only copy.
                guard resolved.standardizedFileURL != destination.standardizedFileURL else { return }
                if files.fileExists(atPath: destination.path) {
                    try files.removeItem(at: destination)
                }
                try files.copyItem(at: resolved, to: destination)
            } catch {
                copyError = error
            }
        }
        if let failure = coordinationError ?? copyError {
            Log.store.error("[CHARTS] could not copy \(source.lastPathComponent, privacy: .public): \(failure.localizedDescription, privacy: .public)")
            #if DEBUG
            FileLog.write("[CHARTS] could not copy \(source.lastPathComponent): \(failure.localizedDescription)")
            #endif
            throw failure
        }

        reload()
        Log.store.info("[CHARTS] added \(source.lastPathComponent, privacy: .public), \(self.charts.count, privacy: .public) held")
        #if DEBUG
        FileLog.write("[CHARTS] added \(source.lastPathComponent), \(charts.count) held")
        #endif
        return Chart(url: destination)
    }

    func remove(_ chart: Chart) {
        do {
            try files.removeItem(at: chart.url)
            Log.store.info("[CHARTS] removed \(chart.id, privacy: .public)")
        } catch {
            Log.store.error("[CHARTS] could not remove \(chart.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    private func reload() {
        let found = (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        charts = found
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map(Chart.init(url:))
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
