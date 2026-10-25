import AVFoundation

/// A hand clap (#53), for the x noteheads a part prints.
///
/// A real clap is not one click: the palms meet in a few places a few
/// milliseconds apart, each a crack of broadband noise, and the last rings
/// on for a moment. So this is four short bursts 7 to 9 ms apart with a tail,
/// band passed around 1.2 kHz, where a clap is loudest and a phone speaker
/// is happy. No pitch in it, on purpose: a student hears at once that the
/// bar is clapped and not played, and the note check has nothing to latch on.
///
/// The noise is from a fixed seed, so every clap is the same clap and a test
/// can compare two renders sample for sample.
enum ClapSound {

    static let duration = 0.15
    /// When each crack lands, and how loud it is against the first.
    private static let bursts: [(at: Double, level: Double)] = [(0, 1), (0.007, 0.75), (0.015, 0.6), (0.024, 0.5)]
    private static let burstDecay = 0.0025
    private static let tailDecay = 0.022
    private static let tailLevel = 0.55
    private static let centre = 1200.0
    private static let q = 0.9

    static func render(volume: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let count = Int(duration * rate)
        guard count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let out = buffer.floatChannelData?[0] else {
            Log.tone.error("[CLAP] would not render at \(rate, privacy: .public) Hz")
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(count)

        // Band pass, RBJ's constant peak gain form.
        let w = 2 * Double.pi * centre / rate
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        let b0 = alpha / a0, b2 = -alpha / a0
        let a1 = -2 * cos(w) / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        let last = bursts[bursts.count - 1].at
        var peak = 0.0
        var samples = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            let noise = Double(seed % 20_001) / 10_000 - 1
            var level = 0.0
            for burst in bursts where t >= burst.at { level += burst.level * exp(-(t - burst.at) / burstDecay) }
            if t >= last { level += tailLevel * exp(-(t - last) / tailDecay) }
            let x = noise * level
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            samples[i] = y
            peak = max(peak, abs(y))
        }
        // As loud as a note's attack at this volume, whatever the filter did.
        let gain = peak > 0 ? volume * 0.8 / peak : 0
        for i in 0..<count { out[i] = Float(samples[i] * gain) }
        return buffer
    }
}
