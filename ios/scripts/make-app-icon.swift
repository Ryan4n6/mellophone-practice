import AppKit
import CoreGraphics
import Foundation

// Turn Sam's 900x900 concept into a shippable App Store icon.
//
// Three things are wrong with the file, none with the design: it is 900 square
// rather than 1024, it carries an alpha channel (Apple rejects transparency),
// and the rounded corners plus black surround are baked in, so iOS would mask
// an already-masked icon and render it shrunken inside a dark frame.
//
// The fix uses only his pixels: find the artwork inside the black margin, then
// crop INTO it, framed on the horn. That drops the "HONK IT UP!" text below the
// frame, which is what we want anyway (the app's name already appears under the
// icon, and at 60 points the text is a smudge), and it makes the horn larger,
// which is exactly what reads at small sizes.

let src = CommandLine.arguments[1]
let dst = CommandLine.arguments[2]
let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "render"

guard
    let data = FileManager.default.contents(atPath: src),
    let provider = CGDataProvider(data: data as CFData),
    let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
else { fatalError("cannot read \(src)") }

let w = image.width, h = image.height

// Read the pixels so the artwork's bounds can be measured rather than guessed.
var pixels = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("no context") }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func isBackdrop(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    let r = Int(pixels[i]), g = Int(pixels[i+1]), b = Int(pixels[i+2]), a = Int(pixels[i+3])
    // Transparent, or the near-black surround around the rounded square.
    return a < 24 || (r < 34 && g < 34 && b < 34)
}

var minX = w, maxX = 0, minY = h, maxY = 0
for y in 0..<h {
    for x in 0..<w where !isBackdrop(x, y) {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}

if mode == "measure" {
    print("image \(w)x\(h)")
    print("artwork bounds x \(minX)...\(maxX)  y \(minY)...\(maxY)")
    print("artwork size \(maxX - minX + 1) x \(maxY - minY + 1)")
    exit(0)
}

// Crop parameters, as fractions of the artwork square, tuned by looking at the
// result. `top` and `height` frame the horn and exclude the text band.
let fracLeft = Double(CommandLine.arguments[4]) ?? 0.04
let fracTop = Double(CommandLine.arguments[5]) ?? 0.02
let fracSize = Double(CommandLine.arguments[6]) ?? 0.74

let artX = Double(minX), artY = Double(minY)
let artW = Double(maxX - minX + 1), artH = Double(maxY - minY + 1)
let side = min(artW, artH) * fracSize
let cropX = artX + artW * fracLeft
let cropY = artY + artH * fracTop

guard let cropped = image.cropping(to: CGRect(x: cropX, y: cropY, width: side, height: side)) else {
    fatalError("crop failed")
}

// Opaque, no alpha channel, exactly 1024 square.
let out = 1024
guard let outCtx = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8,
                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("no output context") }
outCtx.interpolationQuality = .high
outCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))

guard let final = outCtx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: final)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try png.write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) 1024x1024, alpha=\(final.alphaInfo != .none)")
