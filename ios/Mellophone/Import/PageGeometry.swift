import CoreGraphics

/// One glyph, resolved to page coordinates.
///
/// `scalar` is Unicode, already mapped through the font's ToUnicode CMap, so
/// consumers never deal in glyph ids. `font` keeps the BaseFont name with any
/// subset prefix intact ("ABCDEF+Leland") because MusicFontTable does the loose
/// matching and needs the whole string.
struct PlacedGlyph {
    let scalar: UInt32
    let x: Double
    let y: Double
    /// The type size in points, which is the staff's scale: a music font's em
    /// is four staff spaces, so this is how a glyph's drawn size relates to the
    /// staff it sits on.
    let size: Double
    let font: String
}

/// One path, resolved to page coordinates.
///
/// Deliberately uninterpreted. A staff line, a stem, a beam, a barline, a ledger
/// line, a slur and a hairpin are all paths, and telling them apart is a music
/// question that belongs in ScoreBuilder.
struct PlacedPath {
    let vertices: [CGPoint]
    let filled: Bool
    let bounds: CGRect
    /// Drawn with at least one curve segment: a slur, a tie, a notehead
    /// outline. A curve keeps only its endpoint in `vertices`, so this is the
    /// one thing that tells a slur from a straight line of the same size. A
    /// beam is never curved (#39).
    var hasCurves: Bool = false
}

struct PageGeometry {
    let glyphs: [PlacedGlyph]
    let paths: [PlacedPath]

    static let empty = PageGeometry(glyphs: [], paths: [])
}
