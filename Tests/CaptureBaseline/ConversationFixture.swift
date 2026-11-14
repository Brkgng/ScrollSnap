import AppKit
import CoreText

/// Neutral conversation-style content, generated without screenshots or matching markers.
enum ConversationFixture {
    static let viewportHeight = 539

    static func image() -> CGImage {
        let width = 789, height = 3794
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let questions = [
            "How can we plan a small garden for spring?",
            "Which books would suit a quiet afternoon?",
            "What should we pack for a walk beside the river?",
            "Can we arrange the shelves in the reading room?",
            "How would you prepare a simple vegetable soup?",
            "What can we sketch during a visit to the park?",
            "How should we organize a community picnic?",
            "What belongs on the checklist for tomorrow?"
        ]
        let words = "garden river stone meadow cloud lantern path bridge morning leaves orange winter quiet blue silver window paper basket green field library flowers notebook pencil shelf carrot bowl herbs picnic map sketch sunlight water trees room table chair book walk spring supplies"
            .split(separator: " ")
        var state: UInt64 = 1
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 32)
        }
        func draw(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat = 15) {
            let attributed = NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, size, nil),
                .foregroundColor: NSColor(white: 0.7, alpha: 1)
            ])
            context.textPosition = CGPoint(x: x, y: CGFloat(height) - top - size)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        let tops: [CGFloat] = [20, 453, 972, 1402, 1917, 2381, 2907, 3353]
        for (turn, question) in questions.enumerated() {
            let top = tops[turn]
            let nextTop = turn + 1 < tops.count ? tops[turn + 1] : CGFloat(height - 20)
            let bubbleWidth = CGFloat(question.count * 7 + 32)
            let bubbleX = CGFloat(width - 19) - bubbleWidth
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.addPath(CGPath(roundedRect: CGRect(x: bubbleX, y: CGFloat(height) - top - 58,
                                                      width: bubbleWidth, height: 58),
                                   cornerWidth: 16, cornerHeight: 16, transform: nil))
            context.fillPath()
            draw(question, x: bubbleX + 16, top: top + 18)
            let lines = 11 + (turn * 3) % 4
            for line in 0..<lines {
                // Unique text avoids artificial matches between repeated sample paragraphs.
                let count = 8 + next() % 12
                let text = (0..<count).map { _ in words[next() % words.count] }.joined(separator: " ")
                draw(text, x: line % 5 == 3 ? 30 : 12,
                     top: (top + 92 + CGFloat(line) * (nextTop - top - 170) / CGFloat(lines)).rounded())
            }
            if turn % 2 == 0 {
                context.setFillColor(CGColor(gray: 0.12, alpha: 1))
                context.fill(CGRect(x: 12, y: CGFloat(height) - nextTop + 26, width: 758, height: 36))
                draw("Notes: \(question)", x: 28, top: nextTop - 53, size: 14)
            }
        }
        return context.makeImage()!
    }

    static func viewport(document: CGImage, top: Int, scale: Int) -> NSImage {
        let crop = document.cropping(to: CGRect(x: 0, y: top * scale, width: document.width,
                                               height: viewportHeight * scale))!
        return NSImage(cgImage: crop, size: NSSize(width: document.width / scale, height: viewportHeight))
    }

    /// Check each small band so a missing text line cannot disappear into the dark background.
    static func maximumBandMismatch(_ actual: NSImage, expected: NSImage) -> Double? {
        let width = Int(expected.size.width.rounded())
        guard abs(actual.size.width - expected.size.width) <= 1,
              abs(actual.size.height - expected.size.height) <= 1,
              let image = actual.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let crop = image.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(image.width),
                                                  height: expected.size.height * CGFloat(image.height) / actual.size.height)),
              let lhs = FixtureDocument.bitmap(NSImage(cgImage: crop, size: expected.size), width: width),
              let rhs = FixtureDocument.bitmap(expected, width: width), lhs.height == rhs.height else { return nil }
        let a = lhs.data!.assumingMemoryBound(to: UInt8.self)
        let b = rhs.data!.assumingMemoryBound(to: UInt8.self)
        var maximum = 0.0
        for top in stride(from: 0, to: lhs.height, by: 64) {
            var mismatches = 0, samples = 0
            for y in top..<min(top + 64, lhs.height) {
                for x in 0..<width {
                    let offset = y * lhs.bytesPerRow + x * 4
                    // Text and other visible detail matter more than the uniform background.
                    guard (0..<3).contains(where: { max(a[offset + $0], b[offset + $0]) > 40 }) else { continue }
                    samples += 1
                    if (0..<3).contains(where: { abs(Int(a[offset + $0]) - Int(b[offset + $0])) > 12 }) { mismatches += 1 }
                }
            }
            if samples > 0 { maximum = max(maximum, Double(mismatches) / Double(samples)) }
        }
        return maximum
    }
}
