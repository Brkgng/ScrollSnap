//
//  StitchingManager.swift
//  ScrollSnap
//

import AppKit
import Vision

class StitchingManager {
    // MARK: - Properties
    private var runningStitchedImage: NSImage?
    private var previousImage: NSImage? // The most recent screenshot to use for comparison.
    private let stitchingQueue = DispatchQueue(label: "com.scrollsnap.stitching", qos: .userInitiated)
    
    // MARK: - Public API
    
    func startStitching(with initialImage: NSImage) {
        runningStitchedImage = initialImage
        previousImage = initialImage // On start, the initial image is also the previous one.
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
                // If we fail to find an offset, update previousImage and wait for the next one.
                self.previousImage = image
                return
            }

            if offsetInPoints > 0 {
                // Downward scroll: composite the new image onto the bottom of the stitched image.
                guard let newStitchedImage = self.composite(baseImage: baseStitchedImage, newImage: image, offset: offsetInPoints) else {
                    return
                }

                self.runningStitchedImage = newStitchedImage
                self.previousImage = image

            } else if offsetInPoints < 0 {
                // Upward scroll: crop from the bottom of the stitched image.
                let cropAmount = abs(offsetInPoints)

                // Validate crop amount is reasonable.
                guard cropAmount <= baseStitchedImage.size.height,
                      let croppedImage = self.cropBottomRegion(of: baseStitchedImage, byAmount: cropAmount) else {
                    self.previousImage = image
                    return
                }

                self.runningStitchedImage = croppedImage
                self.previousImage = image

            } else {
                // No scroll detected, skip this frame.
                self.previousImage = image
            }
        }
    }
    
    func stopStitching() async -> NSImage? {
        return await withCheckedContinuation { continuation in
            // Enqueue a task to run after all previous tasks on the serial queue.
            // This task will then resume the continuation with the final image.
            stitchingQueue.async { [weak self] in
                continuation.resume(returning: self?.runningStitchedImage)
            }
        }
    }
    
    // MARK: - Private Stitching Methods
    
    private func calculateOffset(from currentImage: NSImage, to previousImage: NSImage) -> CGFloat? {
        guard let currentCG = currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let previousCG = previousImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        guard let verticalOffsetInPixels = findVerticalOffset(from: currentCG, to: previousCG) else {
            return nil
        }

        // Convert the pixel-based offset from Vision to a point-based offset for AppKit drawing.
        guard currentImage.size.height > 0 else { return nil }
        let scale = CGFloat(currentCG.height) / currentImage.size.height
        return verticalOffsetInPixels / (scale > 0 ? scale : 1.0)
    }
    
    private func findVerticalOffset(from image1: CGImage, to image2: CGImage) -> CGFloat? {
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

        // For a downward scroll, the new image (image1) is below the old one (image2).
        // To align image1 with image2, it must be shifted UP, resulting in a positive 'ty' value.
        // For an upward scroll, ty will be negative.
        return observation.alignmentTransform.ty
    }
    
    private func composite(baseImage: NSImage, newImage: NSImage, offset: CGFloat) -> NSImage? {
        let baseSize = baseImage.size
        let newSize = newImage.size
        
        // The total height is the base height plus the new, non-overlapping area (the scroll amount).
        let totalHeight = baseSize.height + offset
        let outputSize = NSSize(width: baseSize.width, height: totalHeight)
        
        let outputImage = NSImage(size: outputSize)
        outputImage.lockFocus()
        
        // Using a standard bottom-up coordinate system for drawing.
        
        // 1. Draw the base image (the stitched result so far) at the TOP of the canvas.
        let baseRect = CGRect(x: 0, y: totalHeight - baseSize.height, width: baseSize.width, height: baseSize.height)
        baseImage.draw(in: baseRect)
        
        // 2. Draw the new image at the BOTTOM of the canvas.
        let newRect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        newImage.draw(in: newRect)
        
        outputImage.unlockFocus()

        return outputImage
    }

    private func cropBottomRegion(of image: NSImage, byAmount amount: CGFloat) -> NSImage? {
        let originalSize = image.size
        guard amount > 0, amount < originalSize.height else { return image }

        let newHeight = originalSize.height - amount
        let newSize = NSSize(width: originalSize.width, height: newHeight)

        let croppedImage = NSImage(size: newSize)
        croppedImage.lockFocus()

        // Keep the top content, crop from the bottom.
        let sourceRect = NSRect(x: 0, y: amount, width: originalSize.width, height: newHeight)
        let destRect = NSRect(origin: .zero, size: newSize)

        image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

        croppedImage.unlockFocus()
        return croppedImage
    }
}
