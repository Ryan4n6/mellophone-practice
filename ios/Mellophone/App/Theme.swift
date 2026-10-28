import SwiftUI

/// The web version's palette, lifted from the `:root` custom properties in
/// `index.html` so the two products look like the same tool. Practising happens
/// in dim rooms and on dark stages, so the app pins dark and does not offer a
/// light variant.
enum Theme {
    static let gold = Color(hex: 0xFFD54F)
    static let goldDim = Color(hex: 0xBFA030)
    static let bg = Color(hex: 0x0E1117)
    static let card = Color(hex: 0x181C25)
    static let cardBorder = Color(hex: 0x252A36)
    static let surface = Color(hex: 0x1E2330)
    static let text = Color(hex: 0xE8EAF0)
    static let textDim = Color(hex: 0x8890A4)
    static let accent = Color(hex: 0x5B8CF7)
    static let green = Color(hex: 0x4CAF50)
    static let red = Color(hex: 0xEF5350)

    static let radius: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The bordered dark panel the web version calls `.card`.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// A point size that follows the phone's text size setting (#66).
///
/// The app was drawn at fixed sizes and rendered identically at the default
/// size and at the largest accessibility size, so a student who had turned
/// text up in Settings got 12 pt gray text anyway. The sizes stay the ones the
/// screens were designed at; `@ScaledMetric` grows each one on the curve of
/// the text style nearest it, so a 12 pt caption and a 40 pt number scale the
/// way Apple's own caption and title do rather than all by one factor.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(for: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// The text style whose default size is nearest, which picks the curve.
    static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: return .largeTitle
        case 24..<30: return .title
        case 21..<24: return .title2
        case 18.5..<21: return .title3
        case 16.5..<18.5: return .body
        case 15.5..<16.5: return .callout
        case 14..<15.5: return .subheadline
        case 12.5..<14: return .footnote
        case 11.5..<12.5: return .caption
        default: return .caption2
        }
    }
}

extension View {
    /// Stops a row of controls growing past the first accessibility size (#66).
    ///
    /// Prose and headings grow all the way. Controls that sit side by side
    /// (a header with a title, the horn and Done; a row of chips; a stepper
    /// with its label between two buttons) do not have the width to: at the
    /// largest sizes the chart's header read "Sampl e...rch" and "D...", and a
    /// stepper "FRO M". Apple caps its own tab bar the same way.
    func controlTextCap() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// `.font(.system(size:weight:design:))`, scaled with the text size setting.
    func scaledFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}
