//
//  StitchingManager.swift
//  ScrollSnap
//

import AppKit
import Vision

enum OffsetEstimateSource: Equatable, Sendable {
    case pixelOverlap
    case fullFrameFallback
}

struct OffsetEstimate: Sendable {
    let translation: CGPoint
    let confidence: Float
    let source: OffsetEstimateSource
}

protocol VerticalOffsetEstimating: Sendable {
    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate?
}

struct VisionOffsetEstimator: VerticalOffsetEstimating {
    func estimate(from currentImage: CGImage, to previousImage: CGImage) -> OffsetEstimate? {
        guard let overlap = PixelOverlap(currentImage, previousImage) else { return nil }
        if overlap.current == overlap.previous {
            return OffsetEstimate(translation: .zero, confidence: 1, source: .pixelOverlap)
        }

        // Vision proposes a translation; the actual overlap must agree before it is used.
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previousImage)
        try? VNImageRequestHandler(cgImage: currentImage, options: [:]).perform([request])
        var proposedOffset: Int?
        if let observation = request.results?.first as? VNImageTranslationAlignmentObservation {
            let translation = observation.alignmentTransform
            if abs(translation.tx) <= 3, abs(translation.ty) <= CGFloat(overlap.maximumOffset) {
                let offset = Int(translation.ty.rounded())
                proposedOffset = offset
                let errors = overlap.columnErrors(at: offset).filter(\.isFinite)
                if abs(offset) <= overlap.maximumOffset,
                   !errors.isEmpty, errors.allSatisfy({ $0 <= 0.05 }) {
                    return OffsetEstimate(translation: CGPoint(x: 0, y: offset),
                                          confidence: observation.confidence, source: .fullFrameFallback)
                }
            }
        }

        // Row summaries shortlist candidates; independent pixel checks decide the offset.
        let coarse = (-overlap.maximumOffset...overlap.maximumOffset)
            .map { (offset: $0, errors: overlap.columnErrors(at: $0, coarse: true)) }
        var offsets: Set<Int> = []
        for column in 0..<3 {
            for candidate in coarse.sorted(by: { $0.errors[column] < $1.errors[column] }).prefix(3) {
                offsets.formUnion(candidate.offset - 2...candidate.offset + 2)
            }
        }
        if let proposedOffset { offsets.formUnion(proposedOffset - 2...proposedOffset + 2) }
        let checked = offsets.filter { abs($0) <= overlap.maximumOffset }
            .map { (offset: $0, errors: overlap.columnErrors(at: $0)) }
        let minima = (0..<3).map { column in checked.map { $0.errors[column] }.min() ?? .infinity }
        // Text antialiasing can change a few grayscale levels during subpixel scrolling.
        let maximumPixelError = 6.0
        let weights = overlap.columnWeights
        let requiredWeight = weights.reduce(0, +) / 2
        let reliable = (0..<3).filter { weights[$0] > 0 && minima[$0] <= maximumPixelError }
        guard reliable.reduce(0, { $0 + weights[$1] }) > requiredWeight else { return nil }
        let agreeing = checked.compactMap { candidate -> (offset: Int, error: Double)? in
            let columns = reliable.filter { column in
                // Subpixel scrolling can rasterize different columns one pixel apart.
                // Keep the error limit and require their best offsets to be adjacent.
                candidate.errors[column] <= maximumPixelError && checked.contains(where: { neighbor in
                    abs(neighbor.offset - candidate.offset) <= 1 && neighbor.errors[column] <= minima[column] + 0.5
                })
            }
            // Header-only columns carry less weight than detail spanning the scrolling body.
            let weight = columns.reduce(0) { $0 + weights[$1] }
            guard weight > requiredWeight else { return nil }
            let error = columns.reduce(0.0) { $0 + candidate.errors[$1] * Double(weights[$1]) } / Double(weight)
            return (offset: candidate.offset, error: error)
        }
        let best = agreeing.min { lhs, rhs in
            lhs.error == rhs.error ? abs(lhs.offset) < abs(rhs.offset) : lhs.error < rhs.error
        }
        guard let best else { return nil }
        return OffsetEstimate(translation: CGPoint(x: 0, y: best.offset), confidence: 1, source: .pixelOverlap)
    }
}

/// A small grayscale sample checks real content while tolerating a pinned header or
/// an animated column. Flat areas alone cannot establish a reliable translation.
private struct PixelOverlap {
    let current: [UInt8]
    let previous: [UInt8]
    private let width: Int
    private let height: Int
    private let currentRows: [RowSignature]
    private let previousRows: [RowSignature]

    private struct RowSignature {
        let mean: Double
        let weightedMean: Double
        let contrast: Int
    }
    var maximumOffset: Int { Int(Double(height) * 0.85) }
    var columnWeights: [Int] {
        (0..<3).map { column in
            let rows = (0..<height).filter { y in
                max(currentRows[y * 3 + column].contrast, previousRows[y * 3 + column].contrast) >= 20
            }
            guard rows.count >= max(4, height / 10), let first = rows.first, let last = rows.last else { return 0 }
            return last - first + 1
        }
    }

    init?(_ currentImage: CGImage, _ previousImage: CGImage) {
        guard currentImage.width == previousImage.width, currentImage.height == previousImage.height,
              currentImage.width >= 3, currentImage.height > 0 else { return nil }
        let width = min(96, currentImage.width)
        let height = currentImage.height
        func pixels(_ image: CGImage) -> [UInt8]? {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                            count: width * height))
        }
        guard let current = pixels(currentImage), let previous = pixels(previousImage) else { return nil }
        func signatures(_ pixels: [UInt8]) -> [RowSignature] {
            let rows = (0..<height * 3).map { index in
                let y = index / 3
                let column = index % 3
                let range = Self.columnRange(column, width: width)
                let start = range.lowerBound
                let end = range.upperBound
                var sum = 0, weighted = 0, weights = 0, low = 255, high = 0
                for x in start..<end {
                    let value = Int(pixels[y * width + x])
                    let weight = (x - start) % 7 + 1
                    sum += value; weighted += value * weight; weights += weight
                    low = min(low, value); high = max(high, value)
                }
                return RowSignature(mean: Double(sum) / Double(end - start),
                                    weightedMean: Double(weighted) / Double(weights), contrast: high - low)
            }
            // Nearby vertical structure can identify movement beneath a textured header.
            let radius = max(1, height / 20)
            return rows.enumerated().map { index, row in
                let y = index / 3, column = index % 3
                let above = rows[max(0, y - radius) * 3 + column]
                let below = rows[min(height - 1, y + radius) * 3 + column]
                // Use vertical detail within flat regions, preserving text whitespace filtering.
                guard row.contrast < 20, above.contrast < 20, below.contrast < 20 else { return row }
                let verticalContrast = max(row.mean, max(above.mean, below.mean)) - min(row.mean, min(above.mean, below.mean))
                return RowSignature(mean: row.mean, weightedMean: row.weightedMean,
                                    contrast: max(row.contrast, Int(verticalContrast)))
            }
        }
        currentRows = signatures(current)
        previousRows = signatures(previous)
        self.current = current
        self.previous = previous
        self.width = width
        self.height = height
    }

    private static func columnRange(_ column: Int, width: Int) -> Range<Int> {
        // Scrollbars and capture borders can change independently of page content.
        let margin = min(3, width / 12)
        return max(margin, column * width / 3)..<min(width - margin, (column + 1) * width / 3)
    }

    func columnErrors(at offset: Int, coarse: Bool = false) -> [Double] {
        let overlapHeight = height - abs(offset)
        guard overlapHeight > 0 else { return Array(repeating: .infinity, count: 3) }
        let sampleCount = min(coarse ? 32 : 128, overlapHeight)
        var columnErrors: [Double] = []
        for column in 0..<3 {
            let range = Self.columnRange(column, width: width)
            let startX = range.lowerBound
            let endX = range.upperBound
            var rowErrors: [Double] = []
            for sample in 0..<sampleCount {
                let y = (sample * 2 + 1) * overlapHeight / (sampleCount * 2)
                let currentRow = (y + max(0, -offset)) * width
                let previousRow = (y + max(0, offset)) * width
                let a = currentRows[(y + max(0, -offset)) * 3 + column]
                let b = previousRows[(y + max(0, offset)) * 3 + column]
                guard max(a.contrast, b.contrast) >= 20 else { continue }
                if coarse {
                    rowErrors.append((abs(a.mean - b.mean) + abs(a.weightedMean - b.weightedMean)) / 2)
                } else {
                    var difference = 0
                    for x in startX..<endX {
                        difference += abs(Int(current[currentRow + x]) - Int(previous[previousRow + x]))
                    }
                    rowErrors.append(Double(difference) / Double(endX - startX))
                }
            }
            guard rowErrors.count >= 4 else { columnErrors.append(.infinity); continue }
            rowErrors.sort()
            // Ignore the worst third of rows, which can contain a stationary header.
            let count = max(1, rowErrors.count * 2 / 3)
            columnErrors.append(rowErrors.prefix(count).reduce(0, +) / Double(count))
        }
        return columnErrors
    }
}

@MainActor
final class StitchingManager {
    private let worker: StitchingWorker
    private var pendingTask: Task<Void, Never>?
    private(set) var isIncomplete = false

    init(offsetEstimator: any VerticalOffsetEstimating = VisionOffsetEstimator()) {
        worker = StitchingWorker(offsetEstimator: offsetEstimator)
    }

    func startStitching(with initialImage: NSImage) {
        isIncomplete = false
        guard let frame = frame(from: initialImage) else { isIncomplete = true; return }
        enqueue { await $0.start(with: frame) }
    }

    func addImage(_ image: NSImage) {
        guard let frame = frame(from: image) else { isIncomplete = true; return }
        enqueue { await $0.add(frame) }
    }

    func waitForPendingImages() async { await pendingTask?.value }

    func stopStitching() async -> NSImage? {
        await waitForPendingImages()
        let (frame, incomplete) = await worker.finish()
        isIncomplete = isIncomplete || incomplete
        pendingTask = nil
        return frame.map { NSImage(cgImage: $0.image, size: $0.size) }
    }

    private func frame(from image: NSImage) -> StitchingFrame? {
        guard image.size.height > 0,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return StitchingFrame(image: cg, size: image.size)
    }

    private func enqueue(_ operation: @escaping @Sendable (StitchingWorker) async -> Void) {
        let previousTask = pendingTask
        let worker = worker
        // Preserve ordering for callers that enqueue frames without awaiting each one.
        pendingTask = Task { await previousTask?.value; await operation(worker) }
    }
}

private struct StitchingFrame: Sendable {
    let image: CGImage
    let size: NSSize
    var scale: CGFloat { CGFloat(image.height) / size.height }
}

/// Owns all processing state off the main actor; only immutable bitmap frames cross actors.
private actor StitchingWorker {
    private var stitched: StitchingFrame?
    private var previous: StitchingFrame?
    private var position = 0
    private var lastAppendHeight = 0
    private var hasUnmatchedFrame = false
    private let offsetEstimator: any VerticalOffsetEstimating

    init(offsetEstimator: any VerticalOffsetEstimating) { self.offsetEstimator = offsetEstimator }

    func start(with frame: StitchingFrame) {
        stitched = frame
        previous = frame
        position = 0
        lastAppendHeight = 0
        hasUnmatchedFrame = false
    }

    func add(_ frame: StitchingFrame) {
        guard let base = stitched, let anchor = previous else { start(with: frame); return }
        guard let estimate = offsetEstimator.estimate(from: frame.image, to: anchor.image) else {
            hasUnmatchedFrame = true
            return // Retain the last reliable anchor so a later frame can catch up.
        }
        let nextPosition = position + Int(estimate.translation.y.rounded())
        let growth = nextPosition + frame.image.height - base.image.height
        // Refresh only recent pixels well inside the viewport, after the page has painted them.
        let refreshHeight = growth >= 0 && lastAppendHeight + growth <= frame.image.height / 2 ? lastAppendHeight : 0
        if growth > 0 || refreshHeight > 0 {
            guard let result = composite(base: base, next: frame, growth: growth, replacing: refreshHeight) else {
                hasUnmatchedFrame = true
                return
            }
            stitched = result
        }
        // Backtracking keeps the captured extent; only content below it is appended.
        position = nextPosition
        lastAppendHeight = max(0, growth)
        previous = frame
        hasUnmatchedFrame = false
    }

    func finish() -> (StitchingFrame?, Bool) {
        let result = (stitched, hasUnmatchedFrame)
        stitched = nil
        previous = nil
        position = 0
        lastAppendHeight = 0
        hasUnmatchedFrame = false
        return result
    }

    private func composite(base: StitchingFrame, next: StitchingFrame, growth: Int, replacing: Int) -> StitchingFrame? {
        guard base.image.width == next.image.width else { return nil }
        let stripHeight = growth + replacing
        guard stripHeight > 0, stripHeight <= next.image.height,
              let strip = next.image.cropping(to: CGRect(x: 0, y: next.image.height - stripHeight,
                                                       width: next.image.width, height: stripHeight)),
              let context = CGContext(data: nil, width: base.image.width, height: base.image.height + growth,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base.image, in: CGRect(x: 0, y: growth, width: base.image.width, height: base.image.height))
        context.draw(strip, in: CGRect(x: 0, y: 0, width: strip.width, height: strip.height))
        guard let output = context.makeImage() else { return nil }
        return StitchingFrame(image: output, size: NSSize(width: base.size.width, height: CGFloat(output.height) / next.scale))
    }

}
