//
//  StitchingManager.swift
//  ScrollSnap
//

import AppKit

class StitchingManager {
    // MARK: - Properties
    private var runningStitchedImage: NSImage?
    private let stitchingQueue = DispatchQueue(label: "com.scrollsnap.stitching", qos: .userInitiated)
    
    // MARK: - Public API
    func startStitching(with initialImage: NSImage) {
        runningStitchedImage = initialImage
    }
    
    func addImage(_ image: NSImage) {
        stitchingQueue.async { [weak self] in
            guard let self = self,
                  let newCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            
            if let baseImage = self.runningStitchedImage,
               let baseCGImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let stitched = self.stitchImagePair(baseCGImage, newCGImage) {
                self.runningStitchedImage = stitched
            } else {
                let size = NSSize(width: newCGImage.width / 2, height: newCGImage.height / 2) // Assuming scaleFactor=2
                self.runningStitchedImage = NSImage(cgImage: newCGImage, size: size)
            }
        }
    }
    
    func stopStitching() -> NSImage? {
        stitchingQueue.sync { } // Wait for all queued tasks to complete
        return runningStitchedImage
    }
    
    // MARK: - Private Stitching Methods
    private func stitchImagePair(_ baseCGImage: CGImage, _ newCGImage: CGImage) -> NSImage? {
        guard baseCGImage.width == newCGImage.width else {
            return NSImage(cgImage: baseCGImage, size: NSSize(width: baseCGImage.width / 2, height: baseCGImage.height / 2))
        }
        
        let width = Int(baseCGImage.width / 2) // Assuming scaleFactor=2
        let baseHeight = baseCGImage.height / 2
        let newHeight = newCGImage.height / 2
        
        let overlap = findOverlapUsingTemplate(baseCGImage, newCGImage)
        let verifiedOverlap = verifyOverlap(overlap, prevImage: baseCGImage, currentImage: newCGImage)
        
        let totalHeight = baseHeight + newHeight - (verifiedOverlap / 2)
        let outputSize = NSSize(width: CGFloat(width), height: CGFloat(totalHeight))
        let outputImage = NSImage(size: outputSize)
        
        outputImage.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            outputImage.unlockFocus()
            return nil
        }
        
        let baseRect = CGRect(x: 0, y: totalHeight - baseHeight, width: width, height: baseHeight)
        context.draw(baseCGImage, in: baseRect)
        
        let newRect = CGRect(x: 0, y: 0, width: width, height: newHeight)
        context.draw(newCGImage, in: newRect)
        
        outputImage.unlockFocus()
        return outputImage
    }
    
    private func findOverlapUsingTemplate(_ topImage: CGImage, _ bottomImage: CGImage) -> Int {
        let width = topImage.width
        let topHeight = topImage.height
        let bottomHeight = bottomImage.height
        let maxOverlap = min(topHeight, bottomHeight)
        let minOverlap = max(20, Int(Double(maxOverlap) * 0.2))
        
        guard let topData = createGrayscaleBitmapData(from: topImage),
              let bottomData = createGrayscaleBitmapData(from: bottomImage) else {
            return minOverlap
        }
        
        let expectedTopSize = topHeight * width // 1 byte per pixel (grayscale)
        let expectedBottomSize = bottomHeight * width
        guard topData.count == expectedTopSize, bottomData.count == expectedBottomSize else {
            return minOverlap
        }
        
        var bestOverlap = minOverlap
        var bestScore = Double.infinity
        
        for overlap in stride(from: maxOverlap, to: minOverlap + 50, by: -10).chain(
            stride(from: minOverlap + 50, to: minOverlap, by: -5)) {
            let topStartY = topHeight - overlap
            var score: Double = 0
            let sampleRate = max(1, width / 200)
            
            for y in stride(from: 0, to: overlap, by: 5) {
                guard y < overlap, topStartY + y < topHeight, y < bottomHeight else {
                    continue
                }
                
                for x in stride(from: 0, to: width, by: sampleRate) {
                    guard x < width else {
                        continue
                    }
                    
                    let topIndex = (topStartY + y) * width + x
                    let bottomIndex = y * width + x
                    
                    guard topIndex < topData.count, bottomIndex < bottomData.count else {
                        continue
                    }
                    
                    let diff = Int(topData[topIndex]) - Int(bottomData[bottomIndex])
                    score += Double(diff * diff)
                }
            }
            
            let samplesPerRow = width / sampleRate
            let rowsCompared = overlap / 5
            let totalPixelsCompared = samplesPerRow * rowsCompared
            score /= Double(totalPixelsCompared) // Only 1 channel, so no * 3
            
            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
            if score < 5 { break }
        }
        return bestOverlap
    }
    
    private func createGrayscaleBitmapData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bitsPerComponent = 8
        let bytesPerRow = width // 1 byte per pixel for grayscale
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue // No alpha for grayscale
        
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &data, width: width, height: height,
                                     bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                     space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let expectedSize = width * height
        guard data.count == expectedSize else {
            return nil
        }
        
        return data
    }
    
    private func verifyOverlap(_ proposedOverlap: Int, prevImage: CGImage, currentImage: CGImage) -> Int {
        let maxOverlap = min(prevImage.height, currentImage.height)
        let minOverlap = max(20, Int(Double(maxOverlap) * 0.2))
        
        // Sanity check - if overlap is too small or too large, use a reasonable default
        if proposedOverlap < minOverlap || proposedOverlap > maxOverlap {
            return Int(Double(maxOverlap) * 0.3) // 30% overlap is usually reasonable
        }
        
        return proposedOverlap
    }
}

// MARK: - Sequence Extension
/// Helper extension to chain two sequences
extension Sequence {
    func chain<S: Sequence>(_ other: S) -> [Element] where S.Element == Element {
        return Array(self) + Array(other)
    }
}
