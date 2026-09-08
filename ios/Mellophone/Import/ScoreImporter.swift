import CoreGraphics
import Foundation

/// Why an import did not produce a score.
///
/// Each case is a different sentence to the user, which is the whole reason
/// there is more than one. "This PDF has no readable notation in it" and "could
/// not find a staff on this page" send someone to different next steps, and
/// collapsing them into one failure sends them to neither.
enum ImportError: Error, Equatable {
    case cannotOpenFile
    case noReadableNotation
    case noStaffFound
}

/// The one entry point the UI calls. Opens the document, picks the engraver
/// table from the fonts actually present, and runs every page through the
/// reader.
///
/// The approach only works because Sam's charts are ENGRAVED, not scanned: the
/// notation arrives as positioned font glyphs with a ToUnicode CMap, so reading
/// them is parsing rather than recognition. That is also its limit. A PDF whose
/// notation has been flattened to vector paths carries no glyphs and yields
/// nothing, and two music PDFs on the build machine are exactly that. This
/// refuses those plainly instead of producing a bad transcription.
enum ScoreImporter {

    static func read(url: URL) -> Score? { try? readOrThrow(url: url) }

    static func readOrThrow(url: URL) throws -> Score {
        // OneDrive registers a File Provider extension, and a file in it is
        // often not materialised locally, so a plain open fails with "no such
        // file". Security-scoped access plus a COORDINATED read is what makes
        // the provider fetch it. Without the coordinator the open can succeed on
        // a placeholder and read zero pages, which looks like an empty score
        // rather than a file that has not downloaded.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var document: CGPDFDocument?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { resolved in
            document = CGPDFDocument(resolved as CFURL)
        }
        if let coordinationError {
            Log.score.error("[IMPORT] could not coordinate a read of \(url.lastPathComponent, privacy: .public): \(coordinationError.localizedDescription, privacy: .public)")
        }
        guard let document else {
            Log.score.error("[IMPORT] cannot open \(url.lastPathComponent, privacy: .public)")
            #if DEBUG
            FileLog.write("[IMPORT] cannot open \(url.lastPathComponent)")
            #endif
            throw ImportError.cannotOpenFile
        }

        var pages: [PageGeometry] = []
        if document.numberOfPages > 0 {
            for index in 1...document.numberOfPages {
                guard let page = document.page(at: index) else { continue }
                pages.append(PDFGlyphReader.read(page: page))
            }
        }

        let fontNames = Set(pages.flatMap { $0.glyphs.map(\.font) })
        guard let table = fontNames.compactMap({ MusicFontTable.forFont($0) }).first else {
            // The font names go in the log on purpose: this is exactly the
            // report needed to add an engraver table, and without it a chart
            // from Finale or Dorico is indistinguishable from a scan.
            Log.score.error("[IMPORT] no music font in \(url.lastPathComponent, privacy: .public), fonts present: \(fontNames.sorted().joined(separator: ", "), privacy: .public)")
            #if DEBUG
            FileLog.write("[IMPORT] no music font, fonts present: \(fontNames.sorted().joined(separator: ", "))")
            #endif
            throw ImportError.noReadableNotation
        }

        let score = ScoreBuilder.build(pages: pages, font: table)
        // A music font with no notes under it means StaffFitter rejected every
        // candidate, which is a different failure from "not a score" and needs a
        // different message.
        guard !score.events.isEmpty else {
            Log.score.error("[IMPORT] music font found in \(url.lastPathComponent, privacy: .public) but no staff systems fitted")
            #if DEBUG
            FileLog.write("[IMPORT] music font found but no staff systems fitted")
            #endif
            throw ImportError.noStaffFound
        }

        Log.score.info("[IMPORT] read \(url.lastPathComponent, privacy: .public): \(pages.count, privacy: .public) pages, \(score.events.count, privacy: .public) events, \(score.suspectMeasures.count, privacy: .public) suspect measures")
        return score
    }
}
