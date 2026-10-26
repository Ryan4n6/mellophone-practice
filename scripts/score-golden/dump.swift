// The iOS chart reader's answer for a PDF, as text (#58).
//
// Built against the app's own Import/ and Audio/ sources by make-golden.sh,
// never by hand, so a golden file is what the shipping Swift reader says.
// scripts/check-score.js prints the same lines from the web app's port and
// expects them to match. Nothing here ships.
//
//   dump <file.pdf>               the score, then the part's timeline
//   GEOM=<page> dump <file.pdf>   one page's glyphs and paths
import AVFoundation
import CoreGraphics
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let env = ProcessInfo.processInfo.environment
func f(_ d: Double) -> String { String(format: "%.4f", d) }

if let spec = env["GEOM"] {
    let doc = CGPDFDocument(url as CFURL)!
    let g = PDFGlyphReader.read(page: doc.page(at: Int(spec)!)!)
    for x in g.glyphs { print("G \(x.font) \(String(format: "%04X", x.scalar)) \(f(x.x)) \(f(x.y)) \(f(x.size))") }
    for p in g.paths {
        let b = p.bounds
        print("P \(p.filled ? "f" : "s")\(p.hasCurves ? "c" : "l") \(p.vertices.count) \(f(b.minX)) \(f(b.maxX)) \(f(b.minY)) \(f(b.maxY)) \(p.vertices.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " "))")
    }
    exit(0)
}

func readScore() -> Score {
    do { return try ScoreImporter.readOrThrow(url: url) } catch { print("ERROR \(error)"); exit(0) }
}
let score = readScore()
for e in score.events {
    let kind = e.isClap ? "clap" : e.isRest ? "rest" : (e.outOfRangeName != nil ? "out" : "note")
    let place = e.place.map { "\($0.system) \(f($0.x)) \(f($0.y))" } ?? "-"
    print("E \(e.measure) v\(e.voice) \(kind) \(e.writtenName.isEmpty ? "-" : e.writtenName) \(e.note?.name ?? "-") on \(f(e.onsetBeats)) dur \(f(e.durationBeats)) tie \(e.tiedFromPrevious ? 1 : 0) at \(place)")
}
for (i, s) in score.systems.enumerated() {
    print("S \(i) page \(s.page) lines \(s.lineYs.map(f).joined(separator: ",")) x \(f(s.xRange.lowerBound))..\(f(s.xRange.upperBound)) hs \(f(s.halfSpace)) ink \(f(s.inkTop)) \(f(s.inkBottom)) bars \(s.bars.map { "\($0.measure):\(f($0.x0))-\(f($0.x1))" }.joined(separator: " "))")
}
print("K key \(score.keySignature) time \(score.timeSignature.beats)/\(score.timeSignature.unit) voices \(score.voiceCount)")
print("U units \(score.beatUnits.keys.sorted().map { "\($0):\(score.beatUnits[$0]!)" }.joined(separator: " "))")
print("X suspect \(score.suspectMeasures.sorted().map(String.init).joined(separator: ","))")
print("Y unreadable \(score.unreadableSymbols.map { String(format: "%04X", $0) }.joined(separator: ","))")
print("T tempos \(score.tempos.map { "\($0.printed)@\($0.measure)/\(f($0.onsetBeats))x\($0.noteQuarters)" }.joined(separator: " "))")
print("R starts \(score.repeats.starts.sorted()) ends \(score.repeats.ends.sorted()) endings \(score.repeats.endings.keys.sorted().map { "\($0):\(score.repeats.endings[$0]!)" })")
func jumpName(_ j: JumpSign) -> String {
    "\(j.back == .daCapo ? "DC" : "DS")-\(j.until == .coda ? "coda" : j.until == .fine ? "fine" : "end")"
}
let r = score.repeats
print("J segno \(r.segno.map(String.init) ?? "-") coda \(r.coda.map(String.init) ?? "-") tocoda \(r.toCoda.map(String.init) ?? "-") fine \(r.fine.map(String.init) ?? "-") jumps \(r.jumps.keys.sorted().map { "\($0):\(jumpName(r.jumps[$0]!))" }.joined(separator: ","))")
print("O order \(PlayOrder.runs(score.playOrder))")

// The whole part at 100 for a mellophone, as Play would lay it out, and the
// first two chunks rendered, by their loudness.
let t = PartTimeline(score: score, voice: .line(0), bars: score.playOrder, bpm: 100, sounding: .mellophone)
print("L duration \(f(t.duration)) spp \(f(t.secondsPerPulse)) countin \(t.countInBeats) pulse \(t.pulse.name)")
for e in t.entries {
    print("N \(e.slot) \(e.event.measure) \(f(e.start)) \(f(e.duration)) \(e.frequency.map(f) ?? "-") \(e.articulation.tonguedIn ? 1 : 0)\(e.articulation.carriesOn ? 1 : 0) \(f(e.articulation.settleCents))")
}
for m in t.measures { print("M \(m.number) \(f(m.start))") }
for s in stride(from: 0.0, to: t.duration, by: 0.37) {
    print("A \(f(s)) \(t.slot(at: s).map(String.init) ?? "-") \(t.measure(at: s).map(String.init) ?? "-") \(t.beat(at: s).map(String.init) ?? "-")")
}
let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
for (i, c) in t.chunks(sampleRate: 48000).enumerated() {
    print("C \(c.startFrame) \(c.frames) \(c.events.count)")
    for e in c.events { print("  e \(f(e.frequency)) \(f(e.onset)) \(f(e.duration)) \(e.isClap ? 1 : 0) \(f(e.brightnessFloor))") }
    if i < 2, let b = ToneSequence.render(events: c.events, volume: 0.5, format: format, frames: AVAudioFrameCount(c.frames)) {
        let data = b.floatChannelData![0]
        var sum: Double = 0, peak: Double = 0
        for k in 0..<Int(b.frameLength) {
            let sample = Double(data[k])
            sum += sample * sample
            peak = Swift.max(peak, Swift.abs(sample))
        }
        let rms = (sum / Double(max(Int(b.frameLength), 1))).squareRoot()
        print("  r \(String(format: "%.9f", rms)) \(String(format: "%.9f", peak))")
    }
}
