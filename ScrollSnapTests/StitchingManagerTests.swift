import AppKit
import XCTest
@testable import ScrollSnap

@MainActor
final class StitchingManagerTests: XCTestCase {
    func testZeroMovementDoesNotChangeHeight() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 3)]))
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

    func testFirstNegativeEstimateDoesNotCrop() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: -20)]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 100)
    }

    func testSecondNegativeEstimateConfirmsCropAgainstUnchangedReference() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([
            estimate(y: -10),
            estimate(y: -20),
        ]))
        manager.startStitching(with: makeBitmapImage())
        manager.addImage(makeBitmapImage())
        manager.addImage(makeBitmapImage())

        let result = await manager.stopStitching()

        XCTAssertEqual(result?.size.height, 80)
    }

    func testFailedMatchClearsPendingReverseMovement() async {
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

        XCTAssertEqual(result?.size.height, 125)
    }

    func testFourBandConsensusRemainsPrimaryPath() {
        let estimator = VisionOffsetEstimator()
        let result = estimator.resolve(
            bandTranslations: [
                translation(y: 40), translation(y: 41), translation(y: 39),
                translation(y: 40), translation(y: 0),
            ],
            fullFrameTranslation: nil,
            frameHeight: 100
        )

        XCTAssertEqual(result?.source, .bandConsensus)
        XCTAssertEqual(result?.translation.y ?? 0, 40, accuracy: 0.01)
    }

    func testThreeBandClusterNeedsConfidentAgreeingFullFrameEstimate() {
        let estimator = VisionOffsetEstimator()
        let bands = [
            translation(y: 40), translation(y: 41), translation(y: 39),
            translation(y: 0), translation(y: 80),
        ]

        let accepted = estimator.resolve(
            bandTranslations: bands,
            fullFrameTranslation: translation(y: 42, confidence: 0.8),
            frameHeight: 100
        )
        let rejected = estimator.resolve(
            bandTranslations: bands,
            fullFrameTranslation: translation(y: 50, confidence: 0.89),
            frameHeight: 100
        )

        XCTAssertEqual(accepted?.source, .validatedBandFallback)
        XCTAssertNil(rejected)
    }

    func testFullFrameFallbackRequiresStrongConfidence() {
        let estimator = VisionOffsetEstimator()
        let bands = [translation(y: 0), translation(y: 20)]

        XCTAssertNil(estimator.resolve(
            bandTranslations: bands,
            fullFrameTranslation: translation(y: 40, confidence: 0.89),
            frameHeight: 100
        ))

        let accepted = estimator.resolve(
            bandTranslations: bands,
            fullFrameTranslation: translation(y: 40, confidence: 0.9),
            frameHeight: 100
        )
        XCTAssertEqual(accepted?.source, .fullFrameFallback)
    }

    func testFallbackRejectsExcessiveHorizontalMotion() {
        let result = VisionOffsetEstimator().resolve(
            bandTranslations: [],
            fullFrameTranslation: translation(x: 4, y: 40, confidence: 1),
            frameHeight: 100
        )

        XCTAssertNil(result)
    }

    func testFallbackRequiresAtLeastFifteenPercentOverlap() {
        let estimator = VisionOffsetEstimator()

        let boundary = estimator.resolve(
            bandTranslations: [],
            fullFrameTranslation: translation(y: 85, confidence: 1),
            frameHeight: 100
        )
        let beyondBoundary = estimator.resolve(
            bandTranslations: [],
            fullFrameTranslation: translation(y: 86, confidence: 1),
            frameHeight: 100
        )

        XCTAssertNotNil(boundary)
        XCTAssertNil(beyondBoundary)
    }

    /// Anything pinned to the bottom edge of the captured window lands in every frame's strip. The
    /// next frame has to repaint it away rather than leave one copy per band.
    func testTrailingTailIsRepaintedFromTheNewestFrame() async {
        let manager = StitchingManager(offsetEstimator: SequenceOffsetEstimator([estimate(y: 20)]))
        manager.startStitching(with: makeSolidImage(blue: true))
        manager.addImage(makeSolidImage(blue: false))

        guard let result = await manager.stopStitching() else {
            return XCTFail("Expected a stitched image")
        }

        XCTAssertEqual(result.size.height, 120)
        // 50 pt up from the bottom sits in territory the base image had already claimed. It must now
        // carry the newest frame's pixels, not the ones stitched a frame ago.
        XCTAssertTrue(isGreen(at: 50, in: result))
        XCTAssertFalse(isGreen(at: 115, in: result), "Content above the repaired tail must stand")
    }

    private func isGreen(at y: CGFloat, in image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let row = min(max(Int(image.size.height - y), 0), bitmap.pixelsHigh - 1)
        guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: row) else { return false }
        return color.greenComponent > 0.5 && color.blueComponent < 0.5
    }

    private func makeSolidImage(blue: Bool) -> NSImage {
        let width = 40, height = 100
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(CGColor(red: 0, green: blue ? 0 : 1, blue: blue ? 1 : 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: width, height: height))
    }

    private func estimate(y: CGFloat) -> OffsetEstimate {
        OffsetEstimate(
            translation: CGPoint(x: 0, y: y),
            confidence: 1,
            source: .bandConsensus
        )
    }

    private func translation(
        x: CGFloat = 0,
        y: CGFloat,
        confidence: Float = 1
    ) -> ImageTranslation {
        ImageTranslation(x: x, y: y, confidence: confidence)
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
    private let lock = NSLock()
    private var estimates: [OffsetEstimate?]

    init(_ estimates: [OffsetEstimate?]) {
        self.estimates = estimates
    }

    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate? {
        lock.lock()
        defer { lock.unlock() }
        return estimates.isEmpty ? nil : estimates.removeFirst()
    }
}
