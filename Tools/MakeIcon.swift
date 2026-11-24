import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Surfaces app icon in a 1024-point design space at any pixel size:
// a desktop panel with a widget card in front of it.
//
//   swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon Surfaces/Media.xcassets/AppIcon.appiconset

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(in ctx: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    let small = pixels <= 32
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale) // top-left origin, 1024 units

    // Background tile on the macOS icon grid (824pt body inside 1024).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = rounded(tile, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0, 0, 0, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0.10, 0.18, 0.40))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: sRGB, colors: [
        color(0.29, 0.58, 0.98),
        color(0.20, 0.36, 0.86),
        color(0.13, 0.17, 0.50),
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 180, y: 100), end: CGPoint(x: 840, y: 924), options: [])

    // The desktop: a wide panel at the back.
    let desktop = CGRect(x: 196, y: 262, width: 632, height: 420)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: color(0, 0, 0, 0.30))
    ctx.addPath(rounded(desktop, 46))
    ctx.setFillColor(color(1, 1, 1, 0.22))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rounded(desktop, 46))
    ctx.setStrokeColor(color(1, 1, 1, 0.55))
    ctx.setLineWidth(small ? 22 : 10)
    ctx.strokePath()

    // The widget: a white card in front, offset down and to the right.
    let card = CGRect(x: 420, y: 470, width: 380, height: 290)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: color(0.02, 0.05, 0.20, 0.45))
    ctx.addPath(rounded(card, 40))
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    if !small {
        // A big number and two lines of text on the card.
        ctx.setFillColor(color(0.16, 0.30, 0.78))
        ctx.addPath(rounded(CGRect(x: 462, y: 516, width: 150, height: 84), 18))
        ctx.fillPath()
        ctx.setFillColor(color(0.70, 0.76, 0.90))
        ctx.addPath(rounded(CGRect(x: 462, y: 630, width: 296, height: 30), 15))
        ctx.addPath(rounded(CGRect(x: 462, y: 684, width: 210, height: 30), 15))
        ctx.fillPath()
    }

    // Subtle top highlight on the tile.
    let sheen = CGGradient(colorsSpace: sRGB, colors: [color(1, 1, 1, 0.16), color(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 420), options: [])
    ctx.restoreGState()
}

func render(pixels: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    draw(in: ctx, pixels: pixels)
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    render(pixels: pixels, to: output.appendingPathComponent("icon_\(pixels).png"))
}
print("done")
