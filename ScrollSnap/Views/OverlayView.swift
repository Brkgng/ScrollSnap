//
//  OverlayView.swift
//  ScrollSnap
//

import SwiftUI

/// `OverlayView` coordinates rendering and event handling across screens using subviews.
class OverlayView: NSView {
    
    // MARK: - Properties
    
    private weak var manager: OverlayManager?
    private var screenFrame: NSRect
    private let selectionRectangleView: SelectionRectangleView
    private var menuBarView: MenuBarView?
    private var hoverTrackingArea: NSTrackingArea?
    private var rectangleTrackingArea: NSTrackingArea?
    private var borderTrackingAreas: [NSTrackingArea] = []
    private var menuTrackingArea: NSTrackingArea?
    
    // MARK: - Initialization
    
    /// Initializes an `OverlayView` with a manager and screen frame.
    /// - Parameters:
    ///   - manager: The `OverlayManager` responsible for managing the overlay.
    ///   - screenFrame: The frame of the screen this overlay is displayed on.
    init(manager: OverlayManager, screenFrame: NSRect) {
        self.manager = manager
        self.screenFrame = screenFrame
        self.selectionRectangleView = SelectionRectangleView(manager: manager, screenFrame: screenFrame)
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        
        self.menuBarView = MenuBarView(manager: manager, screenFrame: screenFrame, overlayView: self)
        updateTrackingAreas()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Mouse Event Overrides
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    // MARK: - Mouse Event Handling
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = manager else { return }
        let localPoint = convertWindowToLocal(point: event.locationInWindow)
        let globalPoint = convertToGlobal(point: localPoint)

        if menuBarView?.handleOpenPopupMouseDown(at: globalPoint) == true {
            return
        }
        
        let menuRect = manager.getMenuRectangle()
        if menuRect.contains(globalPoint) {
            menuBarView?.handleMouseDown(at: globalPoint)
            return
        }
        
        selectionRectangleView.handleMouseDown(at: localPoint)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let localPoint = convertWindowToLocal(point: event.locationInWindow)
        let globalPoint = convertToGlobal(point: localPoint)
        selectionRectangleView.handleMouseDragged(to: globalPoint)
    }

    override func mouseMoved(with event: NSEvent) {
        let localPoint = convertWindowToLocal(point: event.locationInWindow)
        let globalPoint = convertToGlobal(point: localPoint)
        menuBarView?.handleMouseMoved(at: globalPoint)
    }
    
    override func mouseUp(with event: NSEvent) {
        let localPoint = convertWindowToLocal(point: event.locationInWindow)
        let globalPoint = convertToGlobal(point: localPoint)
        selectionRectangleView.handleMouseUp()
        menuBarView?.handleMouseUp(at: globalPoint)
        updateTrackingAreas()
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let manager = manager else { return }
        
        // Draw background only if not in scrolling capture mode
        if manager.getIsScrollingCaptureActive() != true {
            drawBackground(in: dirtyRect)
        }
        
        // Draw subviews
        selectionRectangleView.draw(in: dirtyRect)
        menuBarView?.draw(in: dirtyRect)
    }
    
    func dirtyRect(forGlobalRect rect: NSRect, includesDimensionLabel: Bool) -> NSRect {
        let localRect = convertToLocal(rect: rect)
        
        if includesDimensionLabel {
            return selectionRectangleView.dirtyRect(for: localRect, showsDimensionLabel: true)
        }
        
        return localRect.insetBy(dx: -10, dy: -10).intersection(bounds)
    }
    
    // MARK: - Tracking Area Handling
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let oldRectangleTrackingArea = rectangleTrackingArea {
            removeTrackingArea(oldRectangleTrackingArea)
        }
        borderTrackingAreas.forEach { removeTrackingArea($0) }
        borderTrackingAreas.removeAll()
        
        if let oldMenuTrackingArea = menuTrackingArea {
            removeTrackingArea(oldMenuTrackingArea)
        }
        if let oldHoverTrackingArea = hoverTrackingArea {
            removeTrackingArea(oldHoverTrackingArea)
        }

        let hoverOptions: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        hoverTrackingArea = NSTrackingArea(rect: bounds, options: hoverOptions, owner: self, userInfo: ["type": "overlayHover"])
        addTrackingArea(hoverTrackingArea!)
        
        guard let manager = manager else { return }
        let rectangle = manager.getRectangle()
        let menuRect = manager.getMenuRectangle()
        
        let localRectangle = convertToLocal(rect: rectangle).intersection(bounds)
        let localMenuRect = convertToLocal(rect: menuRect).intersection(bounds)
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if !localRectangle.isEmpty {
            rectangleTrackingArea = NSTrackingArea(rect: localRectangle, options: options, owner: self, userInfo: nil)
            addTrackingArea(rectangleTrackingArea!)
        }
        
        // Border zones
        let zones = selectionRectangleView.calculateBorderZones(for: rectangle, inScreen: screenFrame)
        for (zone, rect) in zones {
            let localZoneRect = rect.intersection(bounds)
            guard !localZoneRect.isEmpty else { continue }
            let trackingArea = NSTrackingArea(rect: localZoneRect, options: options, owner: self, userInfo: ["zone": zone])
            borderTrackingAreas.append(trackingArea)
            addTrackingArea(trackingArea)
        }
        
        if !localMenuRect.isEmpty {
            menuTrackingArea = NSTrackingArea(rect: localMenuRect, options: options, owner: self, userInfo: ["type": "menu"])
            addTrackingArea(menuTrackingArea!)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo else {
            selectionRectangleView.handleMouseEntered()
            return
        }
        
        guard let manager = manager else { return }
        if let type = userInfo["type"] as? String {
            if type == "menu" && manager.getIsScrollingCaptureActive() {
                // Re-enable mouse events so the user can click the menu while scrolling capture is active
                manager.setOverlayIgnoresMouseEvents(false)
            }
        } else if let zone = userInfo["zone"] as? String {
            selectionRectangleView.handleMouseEnteredBorder(zone: zone)
        } else {
            selectionRectangleView.handleMouseEntered()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        guard let userInfo = event.trackingArea?.userInfo else {
            menuBarView?.clearHoverState()
            selectionRectangleView.handleMouseExited()
            return
        }
        
        guard let manager = manager else { return }
        if let type = userInfo["type"] as? String {
            if type == "menu" && manager.getIsScrollingCaptureActive() {
                manager.setOverlayIgnoresMouseEvents(true)
            }
        } else if userInfo["zone"] != nil {
            selectionRectangleView.handleMouseExitedBorder()
        } else {
            selectionRectangleView.handleMouseExited()
        }
    }
    
    // MARK: - Private Drawing Helpers
    
    /// Draws a translucent dark background.
    private func drawBackground(in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.5).setFill()
        rect.fill()
    }
    
    // MARK: - Coordinate Conversion
    
    private func convertWindowToLocal(point: NSPoint) -> NSPoint {
        convert(point, from: nil)
    }
    
    private func convertToLocal(point: NSPoint) -> NSPoint {
        NSPoint(x: point.x - screenFrame.origin.x, y: point.y - screenFrame.origin.y)
    }
    
    private func convertToLocal(rect: NSRect) -> NSRect {
        NSRect(origin: convertToLocal(point: rect.origin), size: rect.size)
    }
    
    /// Converts a local point to global coordinates.
    private func convertToGlobal(point: NSPoint) -> NSPoint {
        NSPoint(x: point.x + screenFrame.origin.x, y: point.y + screenFrame.origin.y)
    }
}
