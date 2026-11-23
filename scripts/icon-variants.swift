// Draws four icon variants (1024 px each) plus a side-by-side sheet with a Dock-size preview.
// Usage: swift scripts/icon-variants.swift <out dir>
import AppKit
import CoreGraphics
import CoreText

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func newCtx(_ w: CGFloat, _ h: CGFloat) -> CGContext {
    let c = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: h); c.scaleBy(x: 1, y: -1)
    return c
}
func rr(_ r: CGRect, _ c: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil) }
func grad(_ ctx: CGContext, _ cols: [UInt32], _ a: CGPoint, _ b: CGPoint) {
    let g = CGGradient(colorsSpace: cs, colors: cols.map { rgb($0) } as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
/// Text drawn with its baseline at y (top-left coordinate space).
func text(_ ctx: CGContext, _ s: String, font: String, size: CGFloat, color: CGColor, centerX: CGFloat, baseline: CGFloat, kern: CGFloat = 0) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): f,
                                                .init(kCTForegroundColorAttributeName as String): color,
                                                .kern: kern]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: centerX - CGFloat(w) / 2, y: baseline)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rr(body, 185)

func tile(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = newCtx(S, S)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0.4))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x17181c)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(bodyPath); ctx.clip()
    draw(ctx)
    ctx.restoreGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0xffffff, 0.07)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

func sprockets(_ ctx: CGContext, band: CGRect, hole: CGSize, gap: CGFloat, inset: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    var x = band.minX + gap / 2
    while x + hole.width <= band.maxX {
        for y in [band.minY + inset, band.maxY - inset - hole.height] {
            ctx.addPath(rr(CGRect(x: x, y: y, width: hole.width, height: hole.height), hole.height * 0.28))
        }
        x += hole.width + gap
    }
    ctx.fillPath()
}

// A — film strip across a dark tile, play button on it
let A = tile { ctx in
    grad(ctx, [0x2b2d34, 0x121317], CGPoint(x: 512, y: 100), CGPoint(x: 512, y: 924))
    let band = CGRect(x: 0, y: 512 - 170, width: S, height: 340)
    ctx.saveGState(); ctx.clip(to: band)
    grad(ctx, [0xf3a95f, 0xe8833a, 0xb9562a], CGPoint(x: 100, y: band.minY), CGPoint(x: 924, y: band.maxY))
    ctx.restoreGState()
    sprockets(ctx, band: band, hole: CGSize(width: 54, height: 36), gap: 40, inset: 24, color: rgb(0x121317))
    let t = CGMutablePath(); let cx: CGFloat = 530, cy: CGFloat = 512, r: CGFloat = 96
    t.move(to: CGPoint(x: cx - r * 0.8, y: cy - r)); t.addLine(to: CGPoint(x: cx + r, y: cy)); t.addLine(to: CGPoint(x: cx - r * 0.8, y: cy + r)); t.closeSubpath()
    ctx.addPath(t); ctx.setFillColor(rgb(0x121317)); ctx.fillPath()
}

// B — orange tile, big dark play button and a sound wave
let B = tile { ctx in
    grad(ctx, [0xf6b067, 0xe8833a, 0xc0592b], CGPoint(x: 150, y: 100), CGPoint(x: 874, y: 924))
    let t = CGMutablePath(); let cx: CGFloat = 540, cy: CGFloat = 430, r: CGFloat = 190
    t.move(to: CGPoint(x: cx - r * 0.8, y: cy - r)); t.addLine(to: CGPoint(x: cx + r, y: cy)); t.addLine(to: CGPoint(x: cx - r * 0.8, y: cy + r)); t.closeSubpath()
    ctx.addPath(t); ctx.setFillColor(rgb(0x17181c)); ctx.fillPath()
    let bars: [CGFloat] = [40, 90, 150, 70, 120, 180, 100, 60, 140, 80, 46]
    let bw: CGFloat = 30, gap: CGFloat = 22
    let total = CGFloat(bars.count) * bw + CGFloat(bars.count - 1) * gap
    var x = 512 - total / 2
    ctx.setFillColor(rgb(0x17181c, 0.9))
    for h in bars { ctx.addPath(rr(CGRect(x: x, y: 760 - h / 2, width: bw, height: h), bw / 2)); x += bw + gap }
    ctx.fillPath()
}

// C — TLR monogram on graphite with an orange film underline
let C = tile { ctx in
    grad(ctx, [0x2b2d34, 0x121317], CGPoint(x: 512, y: 100), CGPoint(x: 512, y: 924))
    text(ctx, "TLR", font: "HelveticaNeue-CondensedBlack", size: 380, color: rgb(0xf2f2f3), centerX: 512, baseline: 600, kern: 6)
    let band = CGRect(x: 170, y: 660, width: 684, height: 120)
    ctx.addPath(rr(band, 18)); ctx.saveGState(); ctx.clip()
    grad(ctx, [0xf3a95f, 0xe8833a, 0xc0592b], CGPoint(x: band.minX, y: 0), CGPoint(x: band.maxX, y: 0))
    ctx.restoreGState()
    sprockets(ctx, band: band, hole: CGSize(width: 36, height: 22), gap: 28, inset: 14, color: rgb(0x121317))
}

// D — clapperboard with orange stripes and a music note
let D = tile { ctx in
    grad(ctx, [0x2b2d34, 0x121317], CGPoint(x: 512, y: 100), CGPoint(x: 512, y: 924))
    let board = CGRect(x: 230, y: 420, width: 564, height: 380)
    ctx.addPath(rr(board, 40)); ctx.setFillColor(rgb(0x0b0b0d)); ctx.fillPath()
    // clapper arm, slightly open
    ctx.saveGState()
    ctx.translateBy(x: 230, y: 400); ctx.rotate(by: -0.20)
    let arm = CGRect(x: 0, y: -110, width: 564, height: 110)
    ctx.addPath(rr(arm, 24)); ctx.clip()
    ctx.setFillColor(rgb(0xe8833a)); ctx.fill(arm)
    ctx.setFillColor(rgb(0x0b0b0d))
    var x: CGFloat = -40
    while x < 600 {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 60, y: 0))
        p.addLine(to: CGPoint(x: x + 130, y: -110)); p.addLine(to: CGPoint(x: x + 70, y: -110)); p.closeSubpath()
        ctx.addPath(p); x += 120
    }
    ctx.fillPath()
    ctx.restoreGState()
    // stripe band on the board top
    let top = CGRect(x: 230, y: 420, width: 564, height: 90)
    ctx.saveGState(); ctx.addPath(rr(board, 40)); ctx.clip()
    ctx.setFillColor(rgb(0xe8833a)); ctx.fill(top)
    ctx.setFillColor(rgb(0x0b0b0d))
    x = 190
    while x < 820 {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x, y: 510)); p.addLine(to: CGPoint(x: x + 60, y: 510))
        p.addLine(to: CGPoint(x: x + 130, y: 420)); p.addLine(to: CGPoint(x: x + 70, y: 420)); p.closeSubpath()
        ctx.addPath(p); x += 120
    }
    ctx.fillPath(); ctx.restoreGState()
    // music note
    ctx.setFillColor(rgb(0xf2f2f3))
    ctx.fillEllipse(in: CGRect(x: 420, y: 650, width: 110, height: 84))
    ctx.fillEllipse(in: CGRect(x: 570, y: 620, width: 110, height: 84))
    ctx.fill(CGRect(x: 512, y: 560, width: 18, height: 130))
    ctx.fill(CGRect(x: 662, y: 530, width: 18, height: 130))
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: 512, y: 560)); beam.addLine(to: CGPoint(x: 680, y: 530))
    beam.addLine(to: CGPoint(x: 680, y: 570)); beam.addLine(to: CGPoint(x: 512, y: 600)); beam.closeSubpath()
    ctx.addPath(beam); ctx.fillPath()
}

let icons = [("A", A), ("B", B), ("C", C), ("D", D)]
for (n, img) in icons {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(dir)/icon_\(n).png"))
}

// sheet: big icons on top, Dock-size (64 px) row underneath on a light and a dark strip
let cell: CGFloat = 440
let sheetW = cell * 4, sheetH: CGFloat = cell + 200
let sh = newCtx(sheetW, sheetH)
sh.setFillColor(rgb(0xececee)); sh.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
sh.setFillColor(rgb(0x2a2b30)); sh.fill(CGRect(x: 0, y: cell + 100, width: sheetW, height: 100))
for (i, (n, img)) in icons.enumerated() {
    let x0 = CGFloat(i) * cell
    func put(_ r: CGRect) {
        sh.saveGState(); sh.translateBy(x: r.minX, y: r.maxY); sh.scaleBy(x: 1, y: -1)
        sh.interpolationQuality = .high
        sh.draw(img, in: CGRect(origin: .zero, size: r.size)); sh.restoreGState()
    }
    put(CGRect(x: x0 + 20, y: 0, width: 400, height: 400))
    text(sh, n, font: "HelveticaNeue-Bold", size: 34, color: rgb(0x333333), centerX: x0 + cell / 2, baseline: 430)
    put(CGRect(x: x0 + cell / 2 - 40, y: cell + 10, width: 80, height: 80))
    put(CGRect(x: x0 + cell / 2 - 40, y: cell + 110, width: 80, height: 80))
}
try! NSBitmapImageRep(cgImage: sh.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "\(dir)/icon_variants.png"))
print("ok")
