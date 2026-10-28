import SwiftUI

/// Which horn the app is set to, on every screen, and the way to change it
/// from wherever you are (#36).
///
/// Every fingering, every concert key and every pitch the microphone is held
/// up to is worked out for one instrument, and until this existed the only
/// place that said which was a picker half way down the Trainer tab. A
/// student on the tuner with the wrong horn selected is told they are a
/// fourth out and has no way to see why. The first time the tuner was used,
/// the phone's log shows it being closed to go and change the instrument.
///
/// It shows the horn itself, drawn (`BrassGlyph`), and its name. The first
/// version drew one generic horn for all four, on the argument that four
/// brass silhouettes this small could not be told apart. Ryan's answer was
/// that the picture has to match the horn or it is not telling anyone
/// anything, and he was right: drawn by what sets each apart, they can be.
struct InstrumentChip: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Menu {
            Picker("Instrument", selection: $prefs.instrument) {
                ForEach(Instrument.allCases) { instrument in
                    Text(instrument.displayName).tag(instrument)
                }
            }
        } label: {
            HStack(spacing: 6) {
                BrassGlyph(kind: prefs.instrument.glyph)
                    .frame(width: 24, height: 17)
                Text(prefs.instrument.shortName)
                    .scaledFont(13, .semibold)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(9, .bold)
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6).frame(minHeight: 30)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.goldDim.opacity(0.6), lineWidth: 1))
            // The capsule is 30 tall because it shares a row with titles. The
            // finger gets the 44 a button is owed.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .controlTextCap()
        }
        .accessibilityLabel("Instrument: \(prefs.instrument.displayName)")
        .accessibilityHint("Changes the instrument the fingerings and pitches are worked out for")
    }
}

extension Instrument {
    /// Which drawing stands for this horn. One each, and a test says so: two
    /// horns sharing a picture is the thing the picture is there to prevent.
    var glyph: BrassGlyph.Kind {
        switch self {
        case .mellophone: return .mellophone
        case .frenchHorn: return .frenchHorn
        case .trumpet: return .trumpet
        case .euphonium: return .euphonium
        }
    }
}
