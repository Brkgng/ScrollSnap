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
        super.init(frame: screenFrame)
        
        self.menuBarView = MenuBarView(manager: manager, screenFrame: screenFrame, overlayView: self)
        updateTrackingAreas()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Mouse Event Handling
    
    override func mouseDown(with event: NSEvent) {
        guard let manager = manager else { return }
        let globalPoint = convertToGlobal(point: event.locationInWindow)
        
        let menuRect = manager.getMenuRectangle()
        if menuRect.contains(globalPoint) {
            menuBarView?.handleMouseDown(at: globalPoint)
            return
        }
        
        selectionRectangleView.handleMouseDown(at: globalPoint)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let globalPoint = convertToGlobal(point: event.locationInWindow)
        selectionRectangleView.handleMouseDragged(to: globalPoint)
        updateTrackingAreas()
    }
    
    override func mouseUp(with event: NSEvent) {
        let globalPoint = convertToGlobal(point: event.locationInWindow)
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
    
    // MARK: - Menu Handling
    
    /// Shows the options menu at the specified location.
    func showOptionsMenu(_ menu: NSMenu, at location: NSPoint) {
        menu.popUp(positioning: nil, at: location, in: self)
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
        
        guard let manager = manager else { return }
        let rectangle = manager.getRectangle()
        let menuRect = manager.getMenuRectangle()
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        rectangleTrackingArea = NSTrackingArea(rect: rectangle, options: options, owner: self, userInfo: nil)
        addTrackingArea(rectangleTrackingArea!)
        
        // Border zones
        let zones = selectionRectangleView.calculateBorderZones(for: rectangle, inScreen: screenFrame)
        for (zone, rect) in zones {
            let trackingArea = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: ["zone": zone])
            borderTrackingAreas.append(trackingArea)
            addTrackingArea(trackingArea)
        }
        
        menuTrackingArea = NSTrackingArea(rect: menuRect, options: options, owner: self, userInfo: ["type": "menu"])
        addTrackingArea(menuTrackingArea!)
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
    
    /// Converts a local point to global coordinates
    private func convertToGlobal(point: NSPoint) -> NSPoint {
        NSPoint(x: point.x + screenFrame.origin.x, y: point.y + screenFrame.origin.y)
    }
}
