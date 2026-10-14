import AppKit
import CoreText
import ImageIO

/// Numbered rows and machine-readable markers share the same source for replay and UI tests.
enum FixtureDocument {
    static let width = 480
    static let viewportHeight = 400
    static let rowHeight = 40
    static let rowCount = 60
    static let height = rowHeight * rowCount

    static func image(scale: Int = 1) -> CGImage {
        let context = CGContext(data: nil, width: width * scale, height: height * scale,
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for row in 0..<rowCount {
            let y = row * rowHeight
            let shade = CGFloat(224 + (row * 17) % 30) / 255
            context.setFillColor(CGColor(gray: shade, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: rowHeight))
            // A fixed prefix, twelve data bits, and a suffix distinguish rows from ordinary text.
            let bits = [1, 0, 1] + (0..<12).map { ((row + 1) >> $0) & 1 } + [0, 1, 0]
            for (index, bit) in bits.enumerated() {
                context.setFillColor(CGColor(gray: bit == 1 ? 0 : 1, alpha: 1))
                context.fill(CGRect(x: 12 + index * 8, y: y + 14, width: 8, height: 12))
            }
            let text = NSAttributedString(string: String(format: "ROW %04d  •  Capture baseline", row + 1),
                                          attributes: [.font: CTFontCreateWithName("Menlo" as CFString, 13, nil),
                                                       .foregroundColor: NSColor.black])
            context.saveGState()
            context.translateBy(x: 168, y: CGFloat(y + 25))
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.restoreGState()
        }
        return context.makeImage()!
    }

    static func expected(document: CGImage, height: Int, scale: Int, pinnedHeader: Bool) -> NSImage {
        let crop = document.cropping(to: CGRect(x: 0, y: 0, width: document.width, height: height * scale))!
        guard pinnedHeader else { return NSImage(cgImage: crop, size: NSSize(width: width, height: height)) }
        let context = CGContext(data: nil, width: document.width, height: height * scale,
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: document.width, height: height * scale))
        context.setFillColor(CGColor(gray: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: (height - 80) * scale, width: document.width, height: 80 * scale))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }

    /// Compare normalized pixels with a small channel tolerance for rasterization/color conversion.
    static func mismatchFraction(_ actual: NSImage, _ expected: NSImage, animated: Bool = false,
                                 width: Int = FixtureDocument.width) -> Double? {
        guard let lhs = bitmap(actual, width: width), let rhs = bitmap(expected, width: width), lhs.height == rhs.height else { return nil }
        let a = lhs.data!.assumingMemoryBound(to: UInt8.self)
        let b = rhs.data!.assumingMemoryBound(to: UInt8.self)
        let comparisonWidth = animated ? 380 : width
        var mismatches = 0
        for y in 0..<lhs.height {
            for x in 0..<comparisonWidth {
                let offset = y * lhs.bytesPerRow + x * 4
                if (0..<3).contains(where: { abs(Int(a[offset + $0]) - Int(b[offset + $0])) > 12 }) { mismatches += 1 }
            }
        }
        return Double(mismatches) / Double(comparisonWidth * lhs.height)
    }

    static func viewport(document: CGImage, top: Int, scale: Int,
                         pinnedHeader: Bool = false, animated: Bool = false) -> NSImage {
        let crop = document.cropping(to: CGRect(x: 0, y: top * scale,
                                                width: width * scale, height: viewportHeight * scale))!
        if !pinnedHeader && !animated {
            return NSImage(cgImage: crop, size: NSSize(width: width, height: viewportHeight))
        }
        let context = CGContext(data: nil, width: width * scale, height: viewportHeight * scale,
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width * scale, height: viewportHeight * scale))
        if pinnedHeader {
            context.setFillColor(CGColor(gray: 0.65, alpha: 1))
            context.fill(CGRect(x: 0, y: (viewportHeight - 80) * scale, width: width * scale, height: 80 * scale))
        }
        if animated {
            context.setFillColor(CGColor(red: CGFloat((top * 13) % 255) / 255, green: 0.5, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 380 * scale, y: 140 * scale, width: 100 * scale, height: 120 * scale))
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: viewportHeight))
    }

    static func rows(in image: NSImage) -> [Int] {
        guard let pixels = bitmap(image) else { return [] }
        let bytes = pixels.data!.assumingMemoryBound(to: UInt8.self)
        var rows: [Int] = []
        var previous: Int?
        for y in 0..<pixels.height {
            let bits = (0..<18).map { index -> Int? in
                let x = 16 + index * 8
                let offset = y * pixels.bytesPerRow + x * 4
                let values = [bytes[offset], bytes[offset + 1], bytes[offset + 2]]
                if values.allSatisfy({ $0 < 45 }) { return 1 }
                if values.allSatisfy({ $0 > 210 }) { return 0 }
                return nil
            }
            guard bits.prefix(3).elementsEqual([1, 0, 1].map(Optional.some)),
                  bits.suffix(3).elementsEqual([0, 1, 0].map(Optional.some)),
                  bits.allSatisfy({ $0 != nil }) else { previous = nil; continue }
            let row = (0..<12).reduce(0) { $0 | (bits[$1 + 3]! << $1) }
            guard (1...rowCount).contains(row) else { previous = nil; continue }
            if previous != row { rows.append(row) }
            previous = row
        }
        return rows
    }

    static func bitmap(_ image: NSImage, width: Int = FixtureDocument.width) -> CGContext? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: width, height: max(1, Int(image.size.height.rounded())),
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: context.height))
        return context
    }

    static func save(_ image: NSImage, to url: URL) throws {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "CaptureBaseline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot encode fixture image"])
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "CaptureBaseline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot write fixture image"])
        }
    }
}
