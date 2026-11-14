import AppKit

/// The body is uniform across every row; only the fixed header has horizontal detail.
enum VerticalDetailFixture: String, CaseIterable {
    case bands, gradient

    static let viewportHeight = 100
    static let headerHeight = 20
    var movement: Int { self == .bands ? 40 : 20 }
    var height: Int { Self.viewportHeight + movement }

    static func headerImage() -> CGImage {
        FixtureDocument.image().cropping(to: CGRect(x: 0, y: 0, width: FixtureDocument.width, height: headerHeight))!
    }

    func image() -> CGImage {
        let width = FixtureDocument.width
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let band = y / 5
            let value = self == .gradient ? UInt8(y * 2) : UInt8(truncatingIfNeeded: band * 73 ^ band * band * 19)
            for x in 0..<width {
                let index = y * context.bytesPerRow + x * 4
                pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value; pixels[index + 3] = 255
            }
        }
        return context.makeImage()!
    }

    func expectedImage() -> NSImage {
        let context = CGContext(data: nil, width: FixtureDocument.width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image(), in: CGRect(x: 0, y: 0, width: FixtureDocument.width, height: height))
        context.draw(Self.headerImage(), in: CGRect(x: 0, y: height - Self.headerHeight,
                                                  width: FixtureDocument.width, height: Self.headerHeight))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: FixtureDocument.width, height: height))
    }

    /// Sample band interiors across the body to detect omissions, duplicates, and wrong order.
    func bodyMismatchFraction(in image: NSImage) -> Double? {
        guard let actual = FixtureDocument.bitmap(image), let expected = FixtureDocument.bitmap(expectedImage()),
              abs(actual.height - height) <= 2 else { return nil }
        let a = actual.data!.assumingMemoryBound(to: UInt8.self)
        let b = expected.data!.assumingMemoryBound(to: UInt8.self)
        var mismatches = 0, samples = 0
        for y in stride(from: Self.headerHeight + 2, to: height - 2, by: 5) {
            for x in [FixtureDocument.width / 4, FixtureDocument.width / 2, FixtureDocument.width * 3 / 4] {
                let left = y * actual.bytesPerRow + x * 4
                let right = y * expected.bytesPerRow + x * 4
                if (0..<3).contains(where: { abs(Int(a[left + $0]) - Int(b[right + $0])) > 12 }) { mismatches += 1 }
                samples += 1
            }
        }
        return Double(mismatches) / Double(samples)
    }
}
