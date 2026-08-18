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
