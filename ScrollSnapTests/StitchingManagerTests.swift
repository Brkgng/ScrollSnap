import AppKit
import CoreText
import os
import XCTest
@testable import ScrollSnap

@MainActor
final class StitchingManagerTests: XCTestCase {
    func testZeroMovementDoesNotChangeHeight() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 0)]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 100)
    }

    func testDownwardMovementAppendsNewContent() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 20)]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 120)
    }

    func testPixelOffsetIsConvertedForRetinaImage() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 40)]))
        manager.startStitching(with: makeBitmapImage(scale: 2))
        manager.addImage(makeBitmapImage(scale: 2))

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 120)
    }

    func testFractionalSelectionSizeDoesNotReportStationaryFrameAsIncomplete() async {
        let image = makeBitmapImage(width: 515, height: 537)
        image.size = NSSize(width: 514.9375, height: 537.16796875)
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 152), estimate(y: 0)]))
        manager.startStitching(with: image)
        manager.addImage(image)
        manager.addImage(image)
        let result = await manager.stopStitching()
        XCTAssertEqual(result?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 689)
        XCTAssertFalse(manager.isIncomplete)
    }

    func testFirstNegativeEstimateDoesNotCrop() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: -20)]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 100)
    }

    func testRepeatedReverseMovementPreservesCapturedContent() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([
            estimate(y: -10),
            estimate(y: -20),
        ]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 100)
    }

    func testFailedMatchDuringReverseMovementPreservesCapturedContent() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([
            estimate(y: -10),
            nil,
            estimate(y: -20),
        ]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 100)
    }

    func testDownUpDownSequencePreservesExpectedHeight() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([
            estimate(y: 30),
            estimate(y: -10),
            estimate(y: -20),
            estimate(y: 15),
        ]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 130)
    }

    func testTinyMovementsPreserveActualContent() async {
        let manager = StitchingManager()
        manager.startStitching(with: scrollingImage(top: 0))
        manager.addImage(scrollingImage(top: 3))
        manager.addImage(scrollingImage(top: 6))
        let result = await manager.stopStitching()
        XCTAssertEqual(result?.size.height, 106)
    }

    func testLaterFrameRefreshesRecentlyAppendedUnpaintedContent() async throws {
        let partial = scrollingImage(top: 20)
        let cg = try XCTUnwrap(partial.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 100, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 40, height: 100))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        let unfinished = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 100))
        let manager = StitchingManager()
        manager.startStitching(with: scrollingImage(top: 0))
        manager.addImage(unfinished)
        manager.addImage(scrollingImage(top: 40))
        let image = await manager.stopStitching()
        let result = try XCTUnwrap(image)
        let output = NSBitmapImageRep(cgImage: try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let expected = NSBitmapImageRep(cgImage: try XCTUnwrap(scrollingImage(top: 100).cgImage(forProposedRect: nil, context: nil, hints: nil)))
        XCTAssertEqual(result.size.height, 140)
        let actualColor = try XCTUnwrap(output.colorAt(x: 10, y: 110)?.usingColorSpace(.sRGB))
        let expectedColor = try XCTUnwrap(expected.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB))
        XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 12.0 / 255)
    }

    func testActualRegistrationKeepsLargeDownwardMovementInTheCorrectDirection() async {
        for scale in [1, 2] {
            let manager = StitchingManager()
            manager.startStitching(with: scrollingImage(top: 0, scale: scale))
            manager.addImage(scrollingImage(top: 80, scale: scale))
            let result = await manager.stopStitching()
            XCTAssertEqual(result?.size.height, 180)
            XCTAssertEqual(result?.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 180 * scale)
        }
    }

    func testStationaryHeaderDoesNotHideMovingContent() {
        let previous = scrollingImage(top: 0, header: true)
        let current = scrollingImage(top: 40, header: true)
        let estimate = VisionOffsetEstimator().estimate(from: current.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                                                        to: previous.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        XCTAssertEqual(estimate?.translation.y, 40)
    }

    func testChangingColumnDoesNotDetermineTheOffset() {
        let previous = scrollingImage(top: 0, animation: true)
        let current = scrollingImage(top: 40, animation: true)
        let estimate = VisionOffsetEstimator().estimate(from: current.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                                                        to: previous.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        XCTAssertEqual(estimate?.translation.y, 40)
    }

    func testMovingColumnDoesNotScrollAStationaryPage() {
        let previous = rasterizedImage(top: 0, middleColumnAdjustment: 0)
        let current = rasterizedImage(top: 0, middleColumnAdjustment: 0, lastColumnAdjustment: 40)
        XCTAssertEqual(VisionOffsetEstimator().estimate(from: current, to: previous)?.translation.y, 0)
    }

    func testNarrowContentDoesNotRequireTextInEveryColumn() {
        let previous = scrollingImage(top: 0, narrow: true)
        let current = scrollingImage(top: 40, narrow: true)
        let estimate = VisionOffsetEstimator().estimate(from: current.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                                                        to: previous.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        XCTAssertEqual(estimate?.translation.y, 40)
    }

    func testPinnedHeaderDoesNotHideNarrowScrollingContent() async throws {
        for scale in [1, 2] {
            for column in 0..<3 {
                let manager = StitchingManager()
                manager.startStitching(with: narrowHeaderImage(top: 0, scale: scale, column: column))
                manager.addImage(narrowHeaderImage(top: 40, scale: scale, column: column))
                let image = await manager.stopStitching()
                let result = try XCTUnwrap(image)
                let expected = narrowHeaderImage(top: 0, scale: scale, column: column, height: 140)
                let actual = NSBitmapImageRep(cgImage: try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil)))
                let reference = NSBitmapImageRep(cgImage: try XCTUnwrap(expected.cgImage(forProposedRect: nil, context: nil, hints: nil)))
                XCTAssertEqual(result.size.height, 140, "scale=\(scale), column=\(column)")
                XCTAssertEqual(actual.pixelsWide, reference.pixelsWide)
                XCTAssertEqual(actual.pixelsHigh, reference.pixelsHigh)
                XCTAssertFalse(manager.isIncomplete)
                guard actual.pixelsWide == reference.pixelsWide, actual.pixelsHigh == reference.pixelsHigh else { continue }
                let pixels = try XCTUnwrap(actual.bitmapData)
                let expectedPixels = try XCTUnwrap(reference.bitmapData)
                var mismatches = 0
                for y in 0..<reference.pixelsHigh {
                    for x in 0..<reference.pixelsWide {
                        let a = y * actual.bytesPerRow + x * 4
                        let b = y * reference.bytesPerRow + x * 4
                        if (0..<3).contains(where: { abs(Int(pixels[a + $0]) - Int(expectedPixels[b + $0])) > 12 }) {
                            mismatches += 1
                        }
                    }
                }
                XCTAssertEqual(mismatches, 0, "scale=\(scale), column=\(column): missing or misplaced pixels")
            }
        }
    }

    func testHorizontalBandsPreserveScrollingContent() async throws {
        for scale in [1, 2] {
            let manager = StitchingManager()
            for top in [0, 40] {
                let image = NSImage(cgImage: horizontalImage(top: top, scale: scale) {
                    UInt8(truncatingIfNeeded: ($0 / 5) * 73 ^ ($0 / 5) * ($0 / 5) * 19)
                }, size: NSSize(width: 96, height: 100))
                if top == 0 { manager.startStitching(with: image) } else { manager.addImage(image) }
            }
            let image = await manager.stopStitching()
            let result = try XCTUnwrap(image)
            XCTAssertEqual(result.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 140 * scale)
            XCTAssertFalse(manager.isIncomplete)
        }
    }

    func testVerticalGradientEstablishesMovement() {
        for scale in [1, 2] {
            let previous = horizontalImage(top: 0, scale: scale) { UInt8($0 * 2) }
            let current = horizontalImage(top: 20, scale: scale) { UInt8($0 * 2) }
            XCTAssertEqual(VisionOffsetEstimator().estimate(from: current, to: previous)?.translation.y, CGFloat(20 * scale))
        }
    }

    func testPinnedHeaderDoesNotHideVerticalBodyDetail() async throws {
        for scale in [1, 2] {
            for gradient in [false, true] {
                let movement = gradient ? 20 : 40
                let rowValue: (Int) -> UInt8 = { row in
                    gradient ? UInt8(row * 2) : UInt8(truncatingIfNeeded: (row / 5) * 73 ^ (row / 5) * (row / 5) * 19)
                }
                let manager = StitchingManager()
                manager.startStitching(with: NSImage(cgImage: horizontalImage(top: 0, scale: scale, header: true, rowValue: rowValue),
                                                     size: NSSize(width: 96, height: 100)))
                manager.addImage(NSImage(cgImage: horizontalImage(top: movement, scale: scale, header: true, rowValue: rowValue),
                                         size: NSSize(width: 96, height: 100)))
                let image = await manager.stopStitching()
                let result = try XCTUnwrap(image)
                XCTAssertEqual(result.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height,
                               (100 + movement) * scale, "gradient=\(gradient), scale=\(scale)")
                XCTAssertFalse(manager.isIncomplete)
            }
        }
    }

    func testDifferentBlankFramesDoNotEstablishMovement() {
        let previous = horizontalImage(top: 0) { _ in 80 }
        let current = horizontalImage(top: 0) { _ in 160 }
        XCTAssertNil(VisionOffsetEstimator().estimate(from: current, to: previous))
    }

    func testUnrelatedHorizontalBandsRemainRejected() {
        let previous = horizontalImage(top: 0) {
            UInt8(truncatingIfNeeded: ($0 / 5) * 73 ^ ($0 / 5) * ($0 / 5) * 19)
        }
        let current = horizontalImage(top: 0) {
            UInt8(truncatingIfNeeded: ($0 / 5) * 97 ^ ($0 / 5) * ($0 / 5) * 31)
        }
        XCTAssertNil(VisionOffsetEstimator().estimate(from: current, to: previous))
    }

    func testOnePixelRasterizationDifferenceDoesNotRejectValidMovement() {
        let previous = rasterizedImage(top: 0, middleColumnAdjustment: 0)
        let current = rasterizedImage(top: 40, middleColumnAdjustment: 1)
        let estimate = VisionOffsetEstimator().estimate(from: current, to: previous)
        XCTAssertEqual(estimate?.translation.y, 40)
    }

    func testDifferentColumnMovementsRemainRejected() {
        let previous = rasterizedImage(top: 0, middleColumnAdjustment: 0)
        let current = rasterizedImage(top: 40, middleColumnAdjustment: 3, lastColumnAdjustment: 6)
        XCTAssertNil(VisionOffsetEstimator().estimate(from: current, to: previous))
    }

    func testSubpixelTextRemainsMatchable() throws {
        let previous = textImage(top: 0)
        let current = textImage(top: 188.5, xShift: 0.2)
        let estimate = try XCTUnwrap(VisionOffsetEstimator().estimate(from: current, to: previous))
        XCTAssertEqual(estimate.translation.y, 188, accuracy: 1)
    }

    func testSeparateTextSectionsDoNotMatchAsReverseMovement() {
        let previous = textImage(top: 0)
        // A repeated text column must not outweigh different text across the rest of the page.
        let current = textImage(top: -400, seed: 1)
        XCTAssertNil(VisionOffsetEstimator().estimate(from: current, to: previous))
    }

    func testUnrelatedContentIsNotAcceptedAsAnOverlap() {
        let previous = scrollingImage(top: 0)
        let current = makeBitmapImage()
        XCTAssertNil(VisionOffsetEstimator().estimate(from: current.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                                                     to: previous.cgImage(forProposedRect: nil, context: nil, hints: nil)!))
    }

    func testUnmatchedFinalFrameIsReportedAsIncomplete() async {
        let manager = StitchingManager()
        manager.startStitching(with: scrollingImage(top: 0))
        manager.addImage(makeBitmapImage())
        let result = await manager.stopStitching()
        XCTAssertEqual(result?.size.height, 100)
        XCTAssertTrue(manager.isIncomplete)
    }

    func testLaterValidOverlapRecoversAnUnmatchedFrame() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([nil, estimate(y: 20)]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())
        let result = await manager.stopStitching()
        XCTAssertEqual(result?.size.height, 120)
        XCTAssertFalse(manager.isIncomplete)
    }

    private func scrollingImage(top: Int, scale: Int = 1, header: Bool = false, animation: Bool = false, narrow: Bool = false) -> NSImage {
        let width = 40 * scale
        let height = 100 * scale
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt8(truncatingIfNeeded: ((x / scale) * 17) ^ ((y / scale + top) * 131))
                if header && y < 20 * scale { value = 80 }
                if animation && x >= width * 2 / 3 { value = UInt8(top + 40) }
                if narrow && x >= width / 3 { value = 255 }
                let index = y * context.bytesPerRow + x * 4
                bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value; bytes[index + 3] = 255
            }
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 40, height: 100))
    }

    private func narrowHeaderImage(top: Int, scale: Int, column: Int, height: Int = 100) -> NSImage {
        let context = CGContext(data: nil, width: 96 * scale, height: height * scale, bitsPerComponent: 8,
                                bytesPerRow: 96 * scale * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height * scale {
            for x in 0..<96 * scale {
                let row = y / scale
                let header = row < 20
                let value: UInt8 = header || x / scale / 32 == column
                    ? UInt8(truncatingIfNeeded: (x / scale) * 17 ^ (row + (header ? 0 : top)) * 131)
                    : 255
                let index = y * context.bytesPerRow + x * 4
                bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value; bytes[index + 3] = 255
            }
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 96, height: height))
    }

    private func horizontalImage(top: Int, scale: Int = 1, header: Bool = false, rowValue: (Int) -> UInt8) -> CGImage {
        let width = 96 * scale, height = 100 * scale
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                bytes[y * width + x] = header && y < 20 * scale
                    ? UInt8(truncatingIfNeeded: (x / scale) * 17 ^ (y / scale) * 131)
                    : rowValue(y / scale + top)
            }
        }
        return context.makeImage()!
    }

    private func rasterizedImage(top: Int, middleColumnAdjustment: Int, lastColumnAdjustment: Int = 0) -> CGImage {
        let width = 96, height = 100
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let adjustment = x < width / 3 ? 0 : (x < width * 2 / 3 ? middleColumnAdjustment : lastColumnAdjustment)
                let row = Double(y + top + adjustment)
                let value = 110 + 50 * sin(Double(x) * 0.27) + 30 * sin(row * 0.031)
                    + 20 * sin(row * 0.083 + Double(x) * 0.014)
                bytes[y * width + x] = UInt8(value.rounded())
            }
        }
        return context.makeImage()!
    }

    private func textImage(top: CGFloat, seed: Int = 0, xShift: CGFloat = 0) -> CGImage {
        let width = 515, height = 537
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let words = "garden river stone meadow cloud lantern path bridge morning leaves orange winter quiet blue silver window paper basket green field"
            .split(separator: " ")
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        for column in 0..<3 {
            context.saveGState()
            context.clip(to: CGRect(x: column * width / 3, y: 0, width: width / 3 + 1, height: height))
            // Keep the first column's text; vary the other columns between independent sections.
            var state = UInt64(column == 0 ? 1 : seed + 1)
            func next() -> Int {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Int(state >> 32)
            }
            for row in 0..<64 {
                let count = 6 + next() % 10
                let line = (0..<count).map { _ in words[next() % words.count] }.joined(separator: " ")
                let text = NSAttributedString(string: line, attributes: [
                    .font: font, .foregroundColor: NSColor(white: 0.7, alpha: 1)
                ])
                context.textPosition = CGPoint(x: 10 + xShift, y: CGFloat(height - 20 - row * 16) + top)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            context.restoreGState()
        }
        return context.makeImage()!
    }

    private func estimate(y: CGFloat) -> OffsetEstimate {
        OffsetEstimate(
            translation: CGPoint(x: 0, y: y),
            confidence: 1,
            source: .pixelOverlap
        )
    }

    private func makeBitmapImage(
        width: CGFloat = 40,
        height: CGFloat = 100,
        scale: CGFloat = 1
    ) -> NSImage {
        let pixelWidth = Int(width * scale)
        let pixelHeight = Int(height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        return NSImage(
            cgImage: context.makeImage()!,
            size: NSSize(width: width, height: height)
        )
    }
}

private final class SequenceOffsetEstimator: VerticalOffsetEstimating {
    private let estimates: OSAllocatedUnfairLock<[OffsetEstimate?]>

    init(_ estimates: [OffsetEstimate?]) { self.estimates = OSAllocatedUnfairLock(initialState: estimates) }

    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate? {
        estimates.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    }
}
