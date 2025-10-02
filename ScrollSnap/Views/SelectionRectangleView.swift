//
//  SelectionRectangleView.swift
//  ScrollSnap
//

import SwiftUI

/// `SelectionRectangleView` manages the selection rectangle's appearance and resizing.
class SelectionRectangleView: NSView {
    
    // MARK: - Properties
    
    private weak var manager: OverlayManager?
    private let screenFrame: NSRect
    private var resizeMode: String?
    
    // MARK: - Initialization
    
    init(manager: OverlayManager, screenFrame: NSRect) {
        self.manager = manager
        self.screenFrame = screenFrame
        super.init(frame: screenFrame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Methods
    
    func draw(in dirtyRect: NSRect) {
        guard let manager = manager else { return }
        let rectangle = manager.getRectangle()
        if rectangle.intersects(screenFrame) {
            drawSelectionRectangle(in: rectangle)
        }
    }
    
    func handleMouseDown(at globalPoint: NSPoint) {
        guard let manager = manager else { return }
        let rectangle = manager.getRectangle()
        
        // Check if capturing - if so, block all interaction
        if manager.getIsScrollingCaptureActive() == true {
            return
        }
        
        // Check border zones first
        resizeMode = findBorderZone(at: globalPoint, for: rectangle)
        if resizeMode != nil {
            return // Start resizing
        }
        
        // If not in a border zone, allow dragging
        if rectangle.contains(globalPoint) {
            NSCursor.closedHand.push()
            manager.handleMouseDown(at: globalPoint)
        }
    }
    
    func handleMouseDragged(to globalPoint: NSPoint) {
        guard let manager = manager else { return }
        
        // Block dragging if capturing
        if manager.getIsScrollingCaptureActive() == true {
            return
        }
        
        if let mode = resizeMode {
            let newRect = resizeRectangle(usingBorder: mode, to: globalPoint)
            manager.updateRectangle(to: newRect)
        } else {
            manager.handleMouseDragged(to: globalPoint)
        }
    }
    
    func handleMouseUp() {
        guard let manager = manager else { return }
        
        // No action if capturing
        if manager.getIsScrollingCaptureActive() == true {
            return
        }
        
        if resizeMode == nil {
            NSCursor.pop() // Revert to hover or default cursor after dragging
        }
        resizeMode = nil
        manager.handleMouseUp()
    }
    
    // MARK: - Cursor Handling
    
    func handleMouseEntered() {
        guard let manager = manager,
              resizeMode == nil // Not resizing
        else { return }
        
        if manager.getIsScrollingCaptureActive() {
            NSCursor.arrow.set()
        } else {
            NSCursor.openHand.set() // Show hand cursor on hover when not capturing
        }
    }
    
    func handleMouseExited() {
        NSCursor.arrow.set() // Reset to default cursor when leaving
    }
    
    func handleMouseEnteredBorder(zone: String) {
        guard let manager = manager,
              manager.getIsScrollingCaptureActive() != true
        else { return }
        
        switch zone {
        case "top":
            NSCursor.resizeUpDown.set()
        case "bottom":
            NSCursor.resizeUpDown.set()
        case "left":
            NSCursor.resizeLeftRight.set()
        case "right":
            NSCursor.resizeLeftRight.set()
        case "topLeft", "topRight", "bottomLeft", "bottomRight":
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }
    
    func handleMouseExitedBorder() {
        if let manager = manager, manager.getRectangle().contains(NSEvent.mouseLocation) {
            // Only set openHand if not capturing
            if manager.getIsScrollingCaptureActive() != true {
                NSCursor.openHand.set() // Revert to hand if still over rectangle
            }
        } else {
            NSCursor.arrow.set()
        }
    }
    
    
    // MARK: - Private Drawing Helpers
    
    /// Draws the selection rectangle with a cleared interior, dashed border, and resizing handles.
    private func drawSelectionRectangle(in rectangle: NSRect) {
        let rectToDraw = rectangle.offsetBy(dx: -screenFrame.origin.x, dy: -screenFrame.origin.y)
        
        clearRectangleArea(in: rectToDraw)
        
        NSColor.white.withAlphaComponent(0.01).setFill()
        NSBezierPath(rect: rectToDraw).fill()
        
        drawDashedBorder(for: rectToDraw)
        
        drawHandles(for: rectToDraw)
    }
    
    /// Clears the interior of the rectangle.
    private func clearRectangleArea(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()
    }
    
    /// Draws a dashed border around the rectangle.
    private func drawDashedBorder(for rect: NSRect) {
        let borderPath = NSBezierPath(rect: rect)
        
        if manager?.getIsScrollingCaptureActive() != true {
            NSColor.white.setStroke() // Default white dashed
            borderPath.lineWidth = Constants.SelectionRectangle.borderWidth
            let dashStyle: [CGFloat] = Constants.SelectionRectangle.borderDashPattern
            borderPath.setLineDash(dashStyle, count: dashStyle.count, phase: 0)
        } else {
            NSColor.red.setStroke() // Solid red during capture
            borderPath.lineWidth = Constants.SelectionRectangle.borderWidth * 2
        }
        
        borderPath.stroke()
    }
    
    /// Draws resizing handles around the rectangle.
    private func drawHandles(for rect: NSRect) {
        // Only draw handles when not capturing
        if manager?.getIsScrollingCaptureActive() == true {
            return
        }
        
        let halfHandle = Constants.SelectionRectangle.handleSize / 2.0
        let handleCenters = calculateHandleCenters(for: rect)
        
        for center in handleCenters {
            let handleRect = NSRect(x: center.x - halfHandle, y: center.y - halfHandle, width: Constants.SelectionRectangle.handleSize, height: Constants.SelectionRectangle.handleSize)
            NSColor.white.setFill()
            NSColor.black.setStroke()
            let handlePath = NSBezierPath(ovalIn: handleRect)
            handlePath.fill()
            handlePath.stroke()
        }
    }
    
    // MARK: - Handle Calculation
    
    /// Calculates the center points of the resizing handles for a given rectangle.
    func calculateHandleCenters(for rect: NSRect) -> [NSPoint] {
        return [
            NSPoint(x: rect.minX, y: rect.minY), // Top-left
            NSPoint(x: rect.midX, y: rect.minY), // Top-center
            NSPoint(x: rect.maxX, y: rect.minY), // Top-right
            NSPoint(x: rect.maxX, y: rect.midY), // Right-center
            NSPoint(x: rect.maxX, y: rect.maxY), // Bottom-right
            NSPoint(x: rect.midX, y: rect.maxY), // Bottom-center
            NSPoint(x: rect.minX, y: rect.maxY), // Bottom-left
            NSPoint(x: rect.minX, y: rect.midY)  // Left-center
        ]
    }
    
    // MARK: - Border Zone Calculation
    
    func calculateBorderZones(for rect: NSRect, inScreen screenFrame: NSRect) -> [String: NSRect] {
        let borderWidth: CGFloat = 20
        let borderPadding: CGFloat = borderWidth / 2
        
        let cornerSize: CGFloat = 40
        let cornerPadding: CGFloat = cornerSize / 2
        
        var zones: [String: NSRect] = [:]
        
        zones["top"] = NSRect(
            x: rect.minX - screenFrame.origin.x + borderWidth,
            y: rect.maxY - screenFrame.origin.y - borderPadding,
            width: rect.width - borderWidth * 2,
            height: borderWidth
        )
        
        zones["bottom"] = NSRect(
            x: rect.minX - screenFrame.origin.x + borderWidth,
            y: rect.minY - screenFrame.origin.y - borderPadding,
            width: rect.width - borderWidth * 2,
            height: borderWidth
        )
        
        zones["left"] = NSRect(
            x: rect.minX - screenFrame.origin.x - borderPadding,
            y: rect.minY - screenFrame.origin.y + borderWidth,
            width: borderWidth,
            height: rect.height - borderWidth * 2
        )
        
        zones["right"] = NSRect(
            x: rect.maxX - screenFrame.origin.x - borderPadding,
            y: rect.minY - screenFrame.origin.y + borderWidth,
            width: borderWidth,
            height: rect.height - borderWidth * 2
        )
        
        zones["topLeft"] = NSRect(
            x: rect.minX - screenFrame.origin.x - cornerPadding,
            y: rect.maxY - screenFrame.origin.y - cornerPadding,
            width: cornerSize,
            height: cornerSize
        )
        
        zones["topRight"] = NSRect(
            x: rect.maxX - screenFrame.origin.x - cornerPadding,
            y: rect.maxY - screenFrame.origin.y - cornerPadding,
            width: cornerSize,
            height: cornerSize
        )
        
        zones["bottomLeft"] = NSRect(
            x: rect.minX - screenFrame.origin.x - cornerPadding,
            y: rect.minY - screenFrame.origin.y - cornerPadding,
            width: cornerSize,
            height: cornerSize
        )
        
        zones["bottomRight"] = NSRect(
            x: rect.maxX - screenFrame.origin.x - cornerPadding,
            y: rect.minY - screenFrame.origin.y - cornerPadding,
            width: cornerSize,
            height: cornerSize
        )
        
        return zones
    }
    
    private func findBorderZone(at point: NSPoint, for rect: NSRect) -> String? {
        let zones = calculateBorderZones(for: rect, inScreen: screenFrame)
        for (zone, zoneRect) in zones {
            if zoneRect.contains(point) {
                return zone
            }
        }
        return nil
    }
    
    // MARK: - Border Resizing
    
    private func resizeRectangle(usingBorder zone: String, to point: NSPoint) -> NSRect {
        guard let manager = manager else { return .zero }
        var rect = manager.getRectangle()
        
        switch zone {
        case "top":
            let newHeight = point.y - rect.minY
            if newHeight > 0 {
                rect.size.height = newHeight
            }
        case "bottom":
            let newHeight = rect.maxY - point.y
            if newHeight > 0 {
                rect.origin.y = point.y
                rect.size.height = newHeight
            }
        case "left":
            let newWidth = rect.maxX - point.x
            if newWidth > 0 {
                rect.origin.x = point.x
                rect.size.width = newWidth
            }
        case "right":
            let newWidth = point.x - rect.minX
            if newWidth > 0 {
                rect.size.width = newWidth
            }
        case "topLeft":
            let newWidth = rect.maxX - point.x
            let newHeight = point.y - rect.minY
            if newWidth > 0 && newHeight > 0 {
                rect.origin.x = point.x
                rect.size.width = newWidth
                rect.size.height = newHeight
            }
        case "topRight":
            let newWidth = point.x - rect.minX
            let newHeight = point.y - rect.minY
            if newWidth > 0 && newHeight > 0 {
                rect.size.width = newWidth
                rect.size.height = newHeight
            }
        case "bottomLeft":
            let newWidth = rect.maxX - point.x
            let newHeight = rect.maxY - point.y
            if newWidth > 0 && newHeight > 0 {
                rect.origin.x = point.x
                rect.origin.y = point.y
                rect.size.width = newWidth
                rect.size.height = newHeight
            }
        case "bottomRight":
            let newWidth = point.x - rect.minX
            let newHeight = rect.maxY - point.y
            if newWidth > 0 && newHeight > 0 {
                rect.origin.y = point.y
                rect.size.width = newWidth
                rect.size.height = newHeight
            }
        default:
            break
        }
        
        return rect
    }
}
