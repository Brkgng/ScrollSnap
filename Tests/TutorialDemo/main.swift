// Render the production overlay over sample content without screen access or desktop input.
import AppKit

// Drawing-only fixture. None of the real capture/session or preference-writing code runs.
final class OverlayManager {
    var rectangle = NSRect(x: 230, y: 270, width: 340, height: 150)
    var capturing = false
    func getRectangle() -> NSRect { rectangle }
    func getMenuRectangle() -> NSRect {
        NSRect(x: (800 - MenuBarLayout.totalWidth) / 2, y: 150,
               width: MenuBarLayout.totalWidth, height: MenuBarLayout.height)
    }
    func getIsScrollingCaptureActive() -> Bool { capturing }
    func updateRectangle(to rect: NSRect) { rectangle = rect }
    func handleMouseDown(at point: NSPoint) {}
    func handleMouseDragged(to point: NSPoint) {}
    func handleMouseUp() {}
    func setOverlayIgnoresMouseEvents(_ value: Bool) {}
    func captureScreenshot() {}
    func dismissOverlay() {}
    func resetPositions() {}
    func openSettings() {}
    func quit() {}
}

let width = 800, height = 520, scale = 2
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
let scrollDistance: CGFloat = 354 // Include the last sentence with clear space below it.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: .aqua)
UserDefaults.standard.register(defaults: [AppLanguage.storageKey: CommandLine.arguments[2]])
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let manager = OverlayManager()
let overlay = OverlayView(manager: manager, screenFrame: bounds)
let menu = MenuBarView(manager: manager, screenFrame: bounds, overlayView: overlay)
let selection = SelectionRectangleView(manager: manager, screenFrame: bounds)

func bitmap(_ draw: () -> Void) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    draw()
    NSGraphicsContext.restoreGraphicsState()
    image.size = bounds.size
    return image
}

func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, bold: Bool = false,
          color: NSColor = .labelColor) {
    (value as NSString).draw(at: NSPoint(x: x, y: top - size * 1.2), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
        .foregroundColor: color
    ])
}

func fill(_ rect: NSRect, color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func article(top: CGFloat) {
    text("WEEKEND NOTES", x: 168, top: top, size: 10, bold: true, color: .systemTeal)
    text("A little room to explore", x: 168, top: top - 25, size: 25, bold: true)
    text("Small plans for a slower day.", x: 168, top: top - 62, size: 13, color: .secondaryLabelColor)
    let headings = ["Take the scenic route", "Make time for a pause", "Bring something home"]
    let lines = [
        ["Start with a quiet walk and see where the path leads.", "Look for a new corner, a little green, or a familiar view."],
        ["Find a sunny spot and stay a little longer.", "Leave enough space in the day for an unexpected stop."],
        ["A photo, a story, or a small idea is enough.", "The best part of a day out is often the simplest."]
    ]
    for index in 0..<3 {
        let y = top - 107 - CGFloat(index) * 160
        fill(NSRect(x: 168, y: y - 52, width: 464, height: 52),
             color: [NSColor.systemTeal, .systemOrange, .systemIndigo][index].withAlphaComponent(0.13), radius: 8)
        text(String(format: "%02d", index + 1), x: 184, top: y - 13, size: 18, bold: true,
             color: [NSColor.systemTeal, .systemOrange, .systemIndigo][index])
        text(headings[index], x: 168, top: y - 68, size: 17, bold: true)
        for (line, value) in lines[index].enumerated() {
            text(value, x: 168, top: y - 98 - CGFloat(line) * 21, size: 13, color: .secondaryLabelColor)
        }
    }
}

func browser(offset: CGFloat) {
    fill(bounds, color: NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.95, alpha: 1))
    fill(NSRect(x: 24, y: 116, width: 752, height: 382), color: .white, radius: 12)
    fill(NSRect(x: 24, y: 462, width: 752, height: 36), color: NSColor(white: 0.95, alpha: 1), radius: 12)
    fill(NSRect(x: 24, y: 462, width: 752, height: 12), color: NSColor(white: 0.95, alpha: 1))
    for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        fill(NSRect(x: 40 + i * 17, y: 476, width: 9, height: 9), color: color, radius: 5)
    }
    fill(NSRect(x: 205, y: 469, width: 390, height: 23), color: .white, radius: 5)
    text("example.com/weekend-notes", x: 305, top: 486, size: 11, color: .secondaryLabelColor)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: NSRect(x: 25, y: 117, width: 750, height: 344)).addClip()
    article(top: 443 + offset)
    NSGraphicsContext.restoreGraphicsState()
    fill(NSRect(x: 765, y: 122, width: 4, height: 334), color: NSColor(white: 0.94, alpha: 1), radius: 2)
    fill(NSRect(x: 765, y: 338 - offset * 0.45, width: 4, height: 105),
         color: NSColor(white: 0.65, alpha: 1), radius: 2)
}

func progress(_ time: Double, _ start: Double, _ end: Double) -> CGFloat {
    let t = CGFloat(min(1, max(0, (time - start) / (end - start))))
    return t * t * (3 - 2 * t)
}
func mix(_ a: NSPoint, _ b: NSPoint, _ p: CGFloat) -> NSPoint {
    NSPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
}
func cursor(at point: NSPoint, click: Bool) {
    if click {
        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)).fill()
    }
    let image = NSCursor.arrow.image
    image.draw(in: NSRect(x: point.x - NSCursor.arrow.hotSpot.x,
                         y: point.y - image.size.height + NSCursor.arrow.hotSpot.y,
                         width: image.size.width, height: image.size.height))
}

// The three caption intervals are 0–4.5 s, 4.5–10 s, and 10–14 s.
for frame in 0..<336 {
    let time = Double(frame) / 24
    let move = progress(time, 0.8, 2.0)
    let resize = progress(time, 2.3, 3.6)
    manager.rectangle = NSRect(x: 230 - move * 78, y: 270 - move * 30 - resize * 22,
                               width: 340 + resize * 156, height: 150 + resize * 58)
    manager.capturing = time >= 4.5 && time < 11.2
    let button = manager.getMenuRectangle()
    let buttonCenter = NSPoint(x: button.maxX - MenuBarLayout.captureWidth / 2, y: button.midY)
    var point = mix(NSPoint(x: 330, y: 350), NSPoint(x: 252, y: 320), move)
    if time >= 2.0 { point = mix(NSPoint(x: 492, y: 240), NSPoint(x: 648, y: 218), resize) }
    if time >= 3.6 { point = mix(NSPoint(x: 648, y: 218), buttonCenter, progress(time, 3.6, 4.3)) }
    if time >= 4.8 { point = mix(buttonCenter, NSPoint(x: 530, y: 310), progress(time, 4.8, 5.3)) }
    if time >= 10 { point = mix(NSPoint(x: 530, y: 310), buttonCenter, progress(time, 10, 10.8)) }
    let clicking = (4.3..<4.65).contains(time) || (10.8..<11.2).contains(time)
    let offset = progress(time, 5.1, 9.8) * scrollDistance
    let overlayImage = bitmap {
        if time < 11.2 {
            if !manager.capturing { NSColor.black.withAlphaComponent(0.45).setFill(); bounds.fill() }
            selection.draw(in: bounds)
            menu.handleMouseMoved(at: point)
            menu.draw(in: bounds)
        }
    }
    let result = bitmap {
        browser(offset: offset)
        NSImage(cgImage: overlayImage.cgImage!, size: bounds.size).draw(in: bounds)
        if (5.4..<9.8).contains(time) {
            let pulse = CGFloat((time * 1.2).truncatingRemainder(dividingBy: 1))
            NSColor.systemBlue.withAlphaComponent(1 - pulse).setStroke()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: point.x + 28, y: point.y + 12 - pulse * 16))
            arrow.line(to: NSPoint(x: point.x + 28, y: point.y - 8 - pulse * 16))
            arrow.move(to: NSPoint(x: point.x + 23, y: point.y - 3 - pulse * 16))
            arrow.line(to: NSPoint(x: point.x + 28, y: point.y - 8 - pulse * 16))
            arrow.line(to: NSPoint(x: point.x + 33, y: point.y - 3 - pulse * 16))
            arrow.lineWidth = 2
            arrow.stroke()
        }
        if time < 11.4 { cursor(at: point, click: clicking) }
        if time >= 11.4 {
            // Present the full sample article as one tall combined image.
            NSColor.black.withAlphaComponent(0.28 * progress(time, 11.4, 11.9)).setFill()
            bounds.fill()
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext.current!.cgContext
            context.translateBy(x: 251, y: 136)
            context.scaleBy(x: 0.60, y: 0.60)
            let captured = NSRect(x: 0, y: 0, width: manager.rectangle.width,
                                  height: manager.rectangle.height + scrollDistance)
            fill(captured, color: .white, radius: 6)
            NSBezierPath(rect: captured).addClip()
            context.translateBy(x: -manager.rectangle.minX, y: scrollDistance - manager.rectangle.minY)
            article(top: 443)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    let data = result.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
}
