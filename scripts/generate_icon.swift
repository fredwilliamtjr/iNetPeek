#!/usr/bin/env swift
import AppKit

// Desenha o ícone a um tamanho arbitrário e devolve um NSBitmapImageRep pronto pra salvar.
func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2237 // squircle-ish macOS

    // Fundo: gradiente azul (cabo) → ciano (wi-fi) — evoca conexão/rede
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(path); cg.clip()
    let colors = [
        CGColor(red: 0.13, green: 0.36, blue: 0.85, alpha: 1),
        CGColor(red: 0.25, green: 0.65, blue: 0.95, alpha: 1),
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    cg.restoreGState()

    // Glyph: SF Symbol "network" em branco, centrado
    let pointSize = size * 0.58
    var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    config = config.applying(.preferringMonochrome())
    guard let base = NSImage(systemSymbolName: "network", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Colore o símbolo de branco usando source-atop
    let tinted = NSImage(size: base.size, flipped: false) { r in
        base.draw(in: r)
        NSColor.white.set()
        r.fill(using: .sourceAtop)
        return true
    }

    let targetRect = NSRect(
        x: (size - tinted.size.width) / 2,
        y: (size - tinted.size.height) / 2,
        width: tinted.size.width,
        height: tinted.size.height
    )
    tinted.draw(in: targetRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try! data.write(to: URL(fileURLWithPath: path))
    print("  wrote \(path) (\(Int(rep.size.width))x\(Int(rep.size.height)))")
}

let defaultTarget = "iNetPeek/Resources/Assets.xcassets/AppIcon.appiconset"
let targetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultTarget

let outputs: [(filename: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

print("Rendering \(outputs.count) PNGs into \(targetDir)")
for o in outputs {
    let rep = renderIcon(size: o.pixels)
    savePNG(rep, to: "\(targetDir)/\(o.filename)")
}
print("Done.")
