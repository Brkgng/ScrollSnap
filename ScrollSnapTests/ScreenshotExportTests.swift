import AppKit
import XCTest
@testable import ScrollSnap

final class ScreenshotExportTests: XCTestCase {
    func testPaperDimensionsAndPageCounts() throws {
        for (paper, width, height) in [
            (PDFPaperSize.a4, 595.275590551, 841.889763780),
            (.letter, 612.0, 792.0)
        ] {
            let image = try makeRowImage(width: 401, height: 2000)
            let document = try pdfDocument(image, paper: paper)
            let rowsPerPage = Int(((height - 72) * 401 / (width - 72)).rounded(.down))
            XCTAssertEqual(document.numberOfPages, (2000 + rowsPerPage - 1) / rowsPerPage)
            for index in 1...document.numberOfPages {
                let page = try XCTUnwrap(document.page(at: index))
                let box = page.getBoxRect(.mediaBox)
                XCTAssertEqual(box.minX, 0)
                XCTAssertEqual(box.minY, 0)
                XCTAssertEqual(box.width, width, accuracy: 0.001)
                XCTAssertEqual(box.height, height, accuracy: 0.001)
                XCTAssertEqual(page.rotationAngle, 0)
            }
        }
    }

    func testEverySourcePixelSurvivesInOrderAcrossPageBoundaries() throws {
        // A non-round scale exercises fractional page geometry and the final partial page.
        for paper in PDFPaperSize.allCases {
            let image = try makeRowImage(width: 401, height: 2189)
            try assertPixelsSurvive(image, paper: paper)
        }
    }

    func testExactPageAndOneRowRemainderDoNotLoseOrDuplicateRows() throws {
        // Letter's printable area is exactly 540 x 720 points at this source width.
        for height in [1, 719, 720, 721, 1440, 1441] {
            let image = try makeRowImage(width: 540, height: height)
            let document = try pdfDocument(image, paper: .letter)
            XCTAssertEqual(document.numberOfPages, (height + 719) / 720)
            try assertPixelsSurvive(image, paper: .letter)
        }
    }

    func testRetinaImageKeepsItsPixelResolution() throws {
        let pixels = try makeRowImage(width: 1080, height: 2882)
        let image = NSImage(cgImage: pixels, size: NSSize(width: 540, height: 1441))
        let exportedPixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(exportedPixels.width, 1080)
        XCTAssertEqual(exportedPixels.height, 2882)
        try assertPixelsSurvive(exportedPixels, paper: .letter)
    }

    func testMarginsAndUnusedLastPageAreWhite() throws {
        let image = try makeRowImage(width: 540, height: 721)
        let document = try pdfDocument(image, paper: .letter)
        let page = try XCTUnwrap(document.page(at: 2))
        let context = try bitmapContext(width: 612, height: 792)
        context.drawPDFPage(page)
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(0, 0), (35, 400), (576, 400), (300, 35), (300, 757), (300, 700)] {
            let offset = (y * 612 + x) * 4
            XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels + offset, count: 4)), [255, 255, 255, 255])
        }
    }

    func testFormatAndPaperPreferencesDefaultAndPersist() throws {
        let name = "ScreenshotExportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ScreenshotFormat.current(userDefaults: defaults), .png)
        XCTAssertEqual(PDFPaperSize.current(userDefaults: defaults), .a4)
        defaults.set("pdf", forKey: ScreenshotFormat.storageKey)
        defaults.set("letter", forKey: PDFPaperSize.storageKey)
        XCTAssertEqual(ScreenshotFormat.current(userDefaults: defaults), .pdf)
        XCTAssertEqual(PDFPaperSize.current(userDefaults: defaults), .letter)
        defaults.set("unknown", forKey: ScreenshotFormat.storageKey)
        defaults.set("unknown", forKey: PDFPaperSize.storageKey)
        XCTAssertEqual(ScreenshotFormat.current(userDefaults: defaults), .png)
        XCTAssertEqual(PDFPaperSize.current(userDefaults: defaults), .a4)
    }

    func testTemporaryDragFileRemainsPNGWhenPDFIsSelected() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ScreenshotFormat.storageKey)
        defaults.set("pdf", forKey: ScreenshotFormat.storageKey)
        defer { defaults.set(previous, forKey: ScreenshotFormat.storageKey) }
        let pixels = try makeRowImage(width: 1080, height: 200)
        let image = NSImage(cgImage: pixels, size: NSSize(width: 540, height: 100))
        let url = try XCTUnwrap(saveImageToTemporaryFile(image))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, 1080)
        XCTAssertEqual(bitmap.pixelsHigh, 200)
    }

    func testTransparentImagePrintsOnWhitePaper() throws {
        let source = try bitmapContext(width: 540, height: 100)
        let document = try pdfDocument(try XCTUnwrap(source.makeImage()), paper: .letter)
        let context = try bitmapContext(width: 612, height: 792)
        context.drawPDFPage(try XCTUnwrap(document.page(at: 1)))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertTrue(UnsafeBufferPointer(start: pixels, count: 612 * 792 * 4).allSatisfy { $0 == 255 })
    }

    private func assertPixelsSurvive(_ image: CGImage, paper: PDFPaperSize) throws {
        let document = try pdfDocument(image, paper: paper)
        let source = try XCTUnwrap(image.dataProvider?.data) as Data
        let scale = (paper.pageSize.width - 72) / CGFloat(image.width)
        let pageRows = Int(((paper.pageSize.height - 72) / scale).rounded(.down))
        var firstRow = 0
        for index in 1...document.numberOfPages {
            let rows = min(pageRows, image.height - firstRow)
            let page = try XCTUnwrap(document.page(at: index))
            // Render only the image region at its original pixel density.
            let context = try bitmapContext(width: image.width, height: rows)
            context.scaleBy(x: 1 / scale, y: 1 / scale)
            context.translateBy(x: -36, y: -(paper.pageSize.height - 36 - CGFloat(rows) * scale))
            context.drawPDFPage(page)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var mismatches = 0
            for row in 0..<rows {
                for column in 0..<image.width {
                    let expectedOffset = (firstRow + row) * image.bytesPerRow + column * 4
                    let actualOffset = (row * image.width + column) * 4
                    for channel in 0..<3 {
                        if abs(Int(source[expectedOffset + channel]) - Int(pixels[actualOffset + channel])) > 2 {
                            mismatches += 1
                        }
                    }
                }
            }
            XCTAssertEqual(mismatches, 0, "\(paper), page \(index), source row \(firstRow)")
            firstRow += rows
        }
        XCTAssertEqual(firstRow, image.height, "All source rows must be present exactly once")
    }

    private func pdfDocument(_ image: CGImage, paper: PDFPaperSize) throws -> CGPDFDocument {
        let data = try XCTUnwrap(ScreenshotPDF.data(for: image, paperSize: paper))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGPDFDocument(provider))
    }

    private func bitmapContext(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
    }

    private func makeRowImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                // Every row and column is identifiable, including individual boundary pixels.
                pixels[offset] = UInt8((row >> 8) % 256)
                pixels[offset + 1] = UInt8(row % 256)
                pixels[offset + 2] = UInt8(column % 251)
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }
}
