// Draws the Reels Studio app icon (1024×1024 PNG).
// Usage: swift scripts/make-icon.swift out.png
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)   // top-left origin

// macOS icon grid: 824×824 body centred, corner ~185
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x17181c)); ctx.fillPath()
ctx.restoreGState()

// body: graphite gradient
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let g = CGGradient(colorsSpace: cs, colors: [rgb(0x2a2c33), rgb(0x141519)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// vertical 9:16 reel frame
let fw: CGFloat = 400, fh: CGFloat = fw * 16 / 9
let frame = CGRect(x: 512 - fw / 2, y: 512 - fh / 2, width: fw, height: fh)
let framePath = CGPath(roundedRect: frame, cornerWidth: 46, cornerHeight: 46, transform: nil)
ctx.addPath(framePath); ctx.setFillColor(rgb(0x0b0b0d)); ctx.fillPath()

// letterbox band with warm film glow
let bandH: CGFloat = 230
let band = CGRect(x: frame.minX, y: 512 - bandH / 2, width: fw, height: bandH)
ctx.saveGState()
ctx.addPath(framePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0xf0a25a), rgb(0xe8833a), rgb(0xb4552a)] as CFArray, locations: [0, 0.55, 1])!
ctx.clip(to: band)
ctx.drawLinearGradient(bg, start: CGPoint(x: band.minX, y: band.minY), end: CGPoint(x: band.maxX, y: band.maxY), options: [])
ctx.restoreGState()

// sprocket holes along the band edges
ctx.setFillColor(rgb(0x0b0b0d))
let holeW: CGFloat = 26, holeH: CGFloat = 18, gap: CGFloat = 22
var x = frame.minX + 20
while x + holeW < frame.maxX - 14 {
    for y in [band.minY + 14, band.maxY - 14 - holeH] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: holeW, height: holeH), cornerWidth: 5, cornerHeight: 5, transform: nil))
    }
    x += holeW + gap
}
ctx.fillPath()

// play triangle in the band
let tri = CGMutablePath()
let cx: CGFloat = 520, cy: CGFloat = 512, r: CGFloat = 62
tri.move(to: CGPoint(x: cx - r * 0.75, y: cy - r))
tri.addLine(to: CGPoint(x: cx + r, y: cy))
tri.addLine(to: CGPoint(x: cx - r * 0.75, y: cy + r))
tri.closeSubpath()
ctx.addPath(tri); ctx.setFillColor(rgb(0x141519)); ctx.fillPath()

// three "word" lines above the band, like lyrics appearing
ctx.setFillColor(rgb(0xe8e8ea, 0.92))
for (i, w) in [CGFloat(210), 150, 250].enumerated() {
    let y = band.minY - 120 + CGFloat(i) * 34
    ctx.addPath(CGPath(roundedRect: CGRect(x: 512 - w / 2, y: y, width: w, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
}
ctx.fillPath()

// frame outline
ctx.addPath(framePath); ctx.setStrokeColor(rgb(0x3a3d45)); ctx.setLineWidth(6); ctx.strokePath()
ctx.restoreGState()

// subtle top highlight on the body
ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0xffffff, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
