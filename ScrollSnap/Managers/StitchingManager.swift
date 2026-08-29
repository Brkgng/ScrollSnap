//
//  StitchingManager.swift
//  ScrollSnap
//

import AppKit
import Vision

enum OffsetEstimateSource: Equatable {
    case bandConsensus
    case validatedBandFallback
    case fullFrameFallback
}

struct OffsetEstimate {
    let translation: CGPoint
    let confidence: Float
    let source: OffsetEstimateSource
}

struct ImageTranslation {
    let x: CGFloat
    let y: CGFloat
    let confidence: Float
}

protocol VerticalOffsetEstimating {
    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate?
}

struct VisionOffsetEstimator: VerticalOffsetEstimating {
    private let comparisonBandCount = 5
    private let minimumComparisonBandHeight = 80
    private let agreementTolerance: CGFloat = 3
    private let maximumHorizontalMovement: CGFloat = 3
    private let minimumOverlapFraction: CGFloat = 0.15
    private let validatedBandConfidence: Float = 0.8
    private let fullFrameConfidence: Float = 0.9

    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate? {
        guard currentImage.width == previousImage.width,
              currentImage.height == previousImage.height else {
            return nil
        }

        let frameHeight = CGFloat(currentImage.height)
        let bandTranslations = comparisonBands(for: currentImage).compactMap { band -> ImageTranslation? in
            guard let currentBand = currentImage.cropping(to: band),
                  let previousBand = previousImage.cropping(to: band),
                  let translation = findTranslation(from: currentBand, to: previousBand),
                  isValid(translation, frameHeight: frameHeight) else {
                return nil
            }
            return translation
        }

        if let consensus = bestGroup(in: bandTranslations, minimumCount: 4) {
            return makeEstimate(from: consensus, source: .bandConsensus)
        }

        let fullFrame = findTranslation(from: currentImage, to: previousImage)
        return resolve(
            bandTranslations: bandTranslations,
            fullFrameTranslation: fullFrame,
            frameHeight: frameHeight
        )
    }

    func resolve(
        bandTranslations: [ImageTranslation],
        fullFrameTranslation: ImageTranslation?,
        frameHeight: CGFloat
    ) -> OffsetEstimate? {
        let validBands = bandTranslations.filter { isValid($0, frameHeight: frameHeight) }

        if let consensus = bestGroup(in: validBands, minimumCount: 4) {
            return makeEstimate(from: consensus, source: .bandConsensus)
        }

        guard let fullFrame = fullFrameTranslation,
              isValid(fullFrame, frameHeight: frameHeight) else { return nil }

        if fullFrame.confidence >= validatedBandConfidence,
           let partialConsensus = bestGroup(in: validBands, minimumCount: 3),
           let bandOffset = average(partialConsensus),
           abs(bandOffset.y - fullFrame.y) <= agreementTolerance {
            return OffsetEstimate(
                translation: CGPoint(x: bandOffset.x, y: bandOffset.y),
                confidence: min(bandOffset.confidence, fullFrame.confidence),
                source: .validatedBandFallback
            )
        }

        guard fullFrame.confidence >= fullFrameConfidence else { return nil }
        return OffsetEstimate(
            translation: CGPoint(x: fullFrame.x, y: fullFrame.y),
            confidence: fullFrame.confidence,
            source: .fullFrameFallback
        )
    }

    private func comparisonBands(for image: CGImage) -> [CGRect] {
        let imageHeight = image.height
        guard image.width > 0, imageHeight > 0 else { return [] }

        let bandHeight = min(imageHeight, max(minimumComparisonBandHeight, imageHeight / 3))
        let maxOriginY = max(0, imageHeight - bandHeight)

        let origins: [Int]
        if maxOriginY == 0 {
            origins = [0]
        } else {
            origins = (0..<comparisonBandCount).map { index in
                let denominator = max(1, comparisonBandCount - 1)
                return Int((CGFloat(maxOriginY) * CGFloat(index) / CGFloat(denominator)).rounded())
            }
        }

        return Array(Set(origins)).sorted().map { originY in
            CGRect(x: 0, y: originY, width: image.width, height: bandHeight)
        }
    }

    private func bestGroup(in translations: [ImageTranslation], minimumCount: Int) -> [ImageTranslation]? {
        var bestGroup: [ImageTranslation] = []

        for translation in translations {
            let group = translations.filter { abs($0.y - translation.y) <= agreementTolerance }
            if group.count > bestGroup.count {
                bestGroup = group
            }
        }

        return bestGroup.count >= minimumCount ? bestGroup : nil
    }

    private func makeEstimate(from translations: [ImageTranslation], source: OffsetEstimateSource) -> OffsetEstimate? {
        guard let translation = average(translations) else { return nil }
        return OffsetEstimate(
            translation: CGPoint(x: translation.x, y: translation.y),
            confidence: translation.confidence,
            source: source
        )
    }

    private func average(_ translations: [ImageTranslation]) -> ImageTranslation? {
        guard !translations.isEmpty else { return nil }
        let count = CGFloat(translations.count)
        return ImageTranslation(
            x: translations.reduce(0) { $0 + $1.x } / count,
            y: translations.reduce(0) { $0 + $1.y } / count,
            confidence: translations.reduce(0) { $0 + $1.confidence } / Float(translations.count)
        )
    }

    private func isValid(_ translation: ImageTranslation, frameHeight: CGFloat) -> Bool {
        let maximumVerticalMovement = frameHeight * (1 - minimumOverlapFraction)
        return abs(translation.x) <= maximumHorizontalMovement
            && abs(translation.y) <= maximumVerticalMovement
    }

    private func findTranslation(from image1: CGImage, to image2: CGImage) -> ImageTranslation? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image2)
        let handler = VNImageRequestHandler(cgImage: image1, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        return ImageTranslation(
            x: observation.alignmentTransform.tx,
            y: observation.alignmentTransform.ty,
            confidence: observation.confidence
        )
    }
}

/// Confines all of its mutable state to `stitchingQueue`, a serial queue, which is what makes the
/// unchecked `Sendable` conformance safe: no property is touched outside that queue.
final class StitchingManager: @unchecked Sendable {
    // MARK: - Properties
    private var runningStitchedImage: NSImage?
    private var previousImage: NSImage? // The most recent screenshot to use for comparison.
    private var hasPendingReverseOffset = false
    private let stitchingQueue = DispatchQueue(label: "com.scrollsnap.stitching", qos: .userInitiated)
    private let offsetEstimator: any VerticalOffsetEstimating
    private let movementDeadZone = Constants.Stitching.movementDeadZone

    init(offsetEstimator: any VerticalOffsetEstimating = VisionOffsetEstimator()) {
        self.offsetEstimator = offsetEstimator
    }
    
    // MARK: - Public API
    
    func startStitching(with initialImage: NSImage) {
        // State is owned by the stitching queue, so seed it there instead of racing with `addImage`.
        stitchingQueue.async { [weak self] in
            guard let self = self else { return }
            self.runningStitchedImage = initialImage
            self.previousImage = initialImage // On start, the initial image is also the previous one.
            self.hasPendingReverseOffset = false
        }
    }
    
    func addImage(_ image: NSImage) {
        stitchingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Ensure we have a base stitched image and a previous image to compare against.
            guard let baseStitchedImage = self.runningStitchedImage,
                  let prevImage = self.previousImage else {
                // This case should ideally not be hit after startStitching is called.
                self.runningStitchedImage = image
                self.previousImage = image
                return
            }
            
            // Calculate the offset by comparing the new image with the *previous* one.
            // This supports both downward scrolling (positive offset) and upward scrolling (negative offset).
            guard let offsetInPoints = self.calculateOffset(from: image, to: prevImage) else {
                // Keep the last reliable reference so the next accepted frame can catch up.
                self.hasPendingReverseOffset = false
                return
            }

            if abs(offsetInPoints) <= self.movementDeadZone {
                self.hasPendingReverseOffset = false
                self.previousImage = image

            } else if offsetInPoints > 0 {
                // Downward scroll: composite the new image onto the bottom of the stitched image.
                guard let newStitchedImage = self.composite(baseImage: baseStitchedImage, newImage: image, offset: offsetInPoints) else {
                    return
                }

                self.hasPendingReverseOffset = false
                self.runningStitchedImage = newStitchedImage
                self.previousImage = image

            } else {
                guard self.hasPendingReverseOffset else {
                    self.hasPendingReverseOffset = true
                    return
                }

                // Upward scroll: crop from the bottom of the stitched image.
                let cropAmount = abs(offsetInPoints)

                // Validate crop amount is reasonable.
                guard cropAmount <= baseStitchedImage.size.height,
                      let croppedImage = self.cropBottomRegion(of: baseStitchedImage, byAmount: cropAmount) else {
                    self.hasPendingReverseOffset = false
                    return
                }

                self.hasPendingReverseOffset = false
                self.runningStitchedImage = croppedImage
                self.previousImage = image
            }
        }
    }
    
    func stopStitching() async -> NSImage? {
        return await withCheckedContinuation { continuation in
            // Enqueue a task to run after all previous tasks on the serial queue.
            // This task will then resume the continuation with the final image.
            stitchingQueue.async { [weak self] in
                let finalImage = self?.runningStitchedImage
                // Clean up state to free memory after stitching completes
                self?.runningStitchedImage = nil
                self?.previousImage = nil
                self?.hasPendingReverseOffset = false
                continuation.resume(returning: finalImage)
            }
        }
    }
    
    // MARK: - Private Stitching Methods
    
    private func calculateOffset(from currentImage: NSImage, to previousImage: NSImage) -> CGFloat? {
        guard let currentCG = currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let previousCG = previousImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let estimate = offsetEstimator.estimate(from: currentCG, to: previousCG) else {
            return nil
        }

        // Convert the pixel-based offset from Vision to a point-based offset for AppKit drawing.
        guard currentImage.size.height > 0 else { return nil }
        let scale = CGFloat(currentCG.height) / currentImage.size.height
        return estimate.translation.y / (scale > 0 ? scale : 1.0)
    }
    
    /// Appends the newly revealed strip of `newImage` below `baseImage`, working in pixels so that
    /// Retina captures keep their full resolution no matter which display the app draws on.
    ///
    /// The sampled strip reaches past the new content into the tail of what is already stitched, so
    /// that region is redrawn from this frame. Content pinned to the bottom edge of the captured
    /// window is stamped into every frame at the same place; by the next frame the real content
    /// underneath it has scrolled clear of the edge, and redrawing replaces the copy with it.
    private func composite(baseImage: NSImage, newImage: NSImage, offset: CGFloat) -> NSImage? {
        guard let baseCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let newCGImage = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let scale = pixelScale(of: baseImage, cgImage: baseCGImage) else {
            return nil
        }

        let newContentHeightInPoints = min(offset, newImage.size.height)
        guard newContentHeightInPoints > 0 else { return nil }

        let newContentHeight = Int((newContentHeightInPoints * scale).rounded())
        guard newContentHeight > 0, newContentHeight <= newCGImage.height else { return nil }

        let outputWidth = baseCGImage.width
        let outputHeight = baseCGImage.height + newContentHeight

        // Reach past the new content into the stitched tail, as far as this frame can supply and the
        // accumulated image can spare.
        let repairHeight = max(0, min(
            Int((Constants.Stitching.trailingRepairHeight * scale).rounded()),
            newCGImage.height - newContentHeight,
            baseCGImage.height
        ))
        let sampledHeight = newContentHeight + repairHeight

        // The strip sits at the bottom of the newest frame, which is the end of a top-left based image.
        guard let newContent = newCGImage.cropping(to: CGRect(
            x: 0,
            y: newCGImage.height - sampledHeight,
            width: newCGImage.width,
            height: sampledHeight
        )), let context = makeContext(width: outputWidth, height: outputHeight) else {
            return nil
        }

        // CGContext draws bottom-up: the accumulated image goes down first, then the sampled strip
        // over it, which both appends the new content and repaints the tail underneath.
        context.draw(baseCGImage, in: CGRect(x: 0, y: newContentHeight, width: outputWidth, height: baseCGImage.height))
        context.draw(newContent, in: CGRect(x: 0, y: 0, width: outputWidth, height: sampledHeight))

        guard let outputImage = context.makeImage() else { return nil }

        return NSImage(cgImage: outputImage, size: pointSize(pixelWidth: outputWidth, pixelHeight: outputHeight, scale: scale))
    }

    private func cropBottomRegion(of image: NSImage, byAmount amount: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard amount > 0, amount < originalSize.height else { return image }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let scale = pixelScale(of: image, cgImage: cgImage) else {
            return nil
        }

        let croppedHeight = cgImage.height - Int((amount * scale).rounded())
        guard croppedHeight > 0 else { return nil }

        // Keep the top content, crop from the bottom.
        guard let croppedImage = cgImage.cropping(to: CGRect(
            x: 0,
            y: 0,
            width: cgImage.width,
            height: croppedHeight
        )) else {
            return nil
        }

        return NSImage(
            cgImage: croppedImage,
            size: pointSize(pixelWidth: cgImage.width, pixelHeight: croppedHeight, scale: scale)
        )
    }

    private func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }

    /// Pixels per point for an image, or `nil` when the image has no usable height.
    private func pixelScale(of image: NSImage, cgImage: CGImage) -> CGFloat? {
        guard image.size.height > 0 else { return nil }
        let scale = CGFloat(cgImage.height) / image.size.height
        return scale > 0 ? scale : nil
    }

    private func pointSize(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> NSSize {
        NSSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
    }
}
