import SwiftUI
import UniformTypeIdentifiers

/// The student's own charts: bring one in, open one, take one out.
///
/// It sits at the top of the Scales tab and not in a tab of its own. iOS shows
/// five tabs before it folds the rest into a "More" list, all five are taken,
/// and a part is the same kind of thing as a scale: something to play back and
/// follow.
struct ChartsCard: View {
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var library = ChartLibrary()
    @StateObject private var player = PartPlayer()
    @State private var isPicking = false
    @State private var opened: Chart?
    @State private var removing: Chart?
    @State private var message: String?
    #if DEBUG
    private static var didAutoOpen = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Charts")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
            // Says which PDFs work BEFORE one is picked. The reader parses the
            // notation a program wrote into the file, so a photo of the same
            // page has nothing in it to read, and finding that out after
            // digging through OneDrive is the worse order.
            Text("Open the PDF of your part and hear how it goes. It has to be the PDF your director made in the notation program, not a scan or a photo.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(library.charts) { chart in
                row(chart)
            }

            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                message = nil
                isPicking = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add a chart")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Theme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .card()
        // The system picker, and nothing of ours. OneDrive shows up in it as a
        // location because OneDrive registers a File Provider, so the band's
        // folder is reachable with no sign-in, no account and no network code
        // in this app.
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                add(url)
            case .failure(let error):
                Log.store.error("[CHARTS] the file picker failed: \(error.localizedDescription, privacy: .public)")
                message = PartModel.message(for: ImportError.cannotOpenFile)
            }
        }
        .fullScreenCover(item: $opened) { chart in
            PartView(chart: chart, onUnreadable: { library.remove($0) }, player: player)
            .environmentObject(prefs)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            "Remove \(removing?.title ?? "this chart")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let removing { library.remove(removing) }
                removing = nil
            }
        } message: {
            Text("This takes it out of the app. The original file is not touched.")
        }
        .onAppear {
            #if DEBUG
            // Opens a chart without the file picker, which a script cannot
            // drive:
            //   xcrun simctl launch booted com.massfeller.mellophone \
            //     -startTab scales -openChart /path/to/chart.pdf
            // Once per launch. This runs every time the tab comes back, and
            // without the flag closing the chart would reopen it.
            if !Self.didAutoOpen, let path = UserDefaults.standard.string(forKey: "openChart") {
                Self.didAutoOpen = true
                add(URL(fileURLWithPath: path))
            }
            #endif
        }
    }

    private func add(_ url: URL) {
        do {
            opened = try library.add(from: url)
        } catch {
            message = PartModel.message(for: ImportError.cannotOpenFile)
        }
    }

    private func row(_ chart: Chart) -> some View {
        HStack(spacing: 8) {
            Button {
                message = nil
                opened = chart
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(Theme.gold)
                    Text(chart.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                removing = chart
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(chart.title)")
        }
    }
}
