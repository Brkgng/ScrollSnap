//
//  OverlayManager.swift
//  ScrollSnap
//

import SwiftUI

class OverlayManager {
    
    // MARK: - Properties
    
    private var rectangle: NSRect
    private var menuRect: NSRect
    private var draggingRectangle = false
    private var draggingMenu = false
    private var dragOffset: NSPoint = .zero
    private var overlayWindows: [NSWindow] = []
    private var isScrollingCaptureActive = false
    private var captureTimer: Timer?
    private let stitchingManager = StitchingManager()
    var thumbnailWindow: NSWindow?
    
    // MARK: - Initialization
    
    init() {
        /// Load the last saved rectangle position or use the default
        rectangle = Self.loadRectangle()
        
        /// Load the last saved menu position or position it 20px below the rectangle
        menuRect = Self.loadMenuRect(for: rectangle)
    }
    
    // MARK: - Public API
    
    /// Sets up overlays on all available screens.
    func setupOverlays() {
        overlayWindows = NSScreen.screens.map { screen in
            let overlayWindow = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            overlayWindow.level = .statusBar
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let overlayView = OverlayView(manager: self, screenFrame: screen.frame)
            overlayWindow.contentView = overlayView
            
            return overlayWindow
        }
        
        // After creating all overlays, focus the one with the selection rectangle
        if let primaryOverlay = overlayWindows.first(where: { $0.frame.contains(rectangle.origin) }) {
            primaryOverlay.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) // Ensure the app is active
        }
    }
    
    /// Updates the rectangle and persists it to UserDefaults. Refreshes all overlays.
    func updateRectangle(to newRect: NSRect) {
        rectangle = clampRectangleToScreens(rect: newRect)
        saveRectangle(rectangle)
        
        // Ensure the overlay window containing the rectangle is frontmost
        if let targetOverlay = overlayWindows.first(where: { $0.frame.contains(rectangle.origin) }) {
            // Bring the target overlay to the front and make it key
            targetOverlay.makeKeyAndOrderFront(nil)
        }
        
        refreshOverlays()
    }
    
    /// Updates the menu rectangle. Refreshes all overlays.
    func updateMenuRect(to newRect: NSRect) {
        let clampedRect = clampRectangleToScreens(rect: newRect)
        menuRect = clampedRect
        saveMenuRect(menuRect)
        refreshOverlays()
    }
    
    /// Returns the current rectangle.
    func getRectangle() -> NSRect {
        return rectangle
    }
    
    /// Returns the current menu rectangle.
    func getMenuRectangle() -> NSRect {
        return menuRect
    }
    
    /// Returns whether scrolling capture is active.
    func getIsScrollingCaptureActive() -> Bool {
        return isScrollingCaptureActive
    }
    
    /// Handles mouse down events. Determines if the click was within the rectangle or menu.
    func handleMouseDown(at point: NSPoint) {
        if menuRect.contains(point) {
            startDragging(menu: true, at: point)
        } else if rectangle.contains(point) {
            startDragging(rectangle: true, at: point)
        }
    }
    
    /// Handles mouse dragged events, updating the appropriate rectangle.
    func handleMouseDragged(to point: NSPoint) {
        if draggingMenu {
            let newOrigin = NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
            let newMenuRect = NSRect(origin: newOrigin, size: menuRect.size)
            updateMenuRect(to: newMenuRect)
        } else if draggingRectangle {
            let newOrigin = NSPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
            let newRectangle = NSRect(origin: newOrigin, size: rectangle.size)
            updateRectangle(to: newRectangle)
        }
    }
    
    /// Handles mouse up
    func handleMouseUp() {
        stopDragging()
    }
    
    /// Initiates or stops screenshot capture based on current mode.
    func captureScreenshot() {
        Task {
            if isScrollingCaptureActive {
                await stopScrollingCapture()
            } else {
                await startScrollingCapture()
            }
        }
    }
    
    /// Stops the scrolling capture process and saves collected images.
    private func stopScrollingCapture() async {
        isScrollingCaptureActive = false
        
        await MainActor.run {
            invalidateCaptureTimer()
            hideOverlays()
            if let finalImage = stitchingManager.stopStitching() {
                let selectedDestination = UserDefaults.standard.string(forKey: Constants.Menu.Options.selectedDestinationKey) ?? Constants.Menu.Options.defaultDestination
                
                switch selectedDestination {
                case "Clipboard", "Preview":
                    saveImage(finalImage)
                default:
                    showThumbnail(with: finalImage)
                }
            }
        }
    }
    
    /// Starts the scrolling capture process.
    private func startScrollingCapture() async {
        isScrollingCaptureActive = true
        
        if let image = await captureSingleScreenshot(rectangle) {
            stitchingManager.startStitching(with: image)
        }
        
        await MainActor.run {
            setupCaptureTimer()
            refreshOverlays()
        }
    }
    
    private func setupCaptureTimer() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isScrollingCaptureActive else { return }
            
            Task {
                await self.handleTimerCapture()
            }
        }
    }
    
    /// Handles capture operations triggered by timer.
    private func handleTimerCapture() async {
        if let newImage = await captureSingleScreenshot(rectangle) {
            stitchingManager.addImage(newImage)
        }
    }
    
    private func invalidateCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    // MARK: - Thumbnail Management
    
    private func showThumbnail(with image: NSImage) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rectangle.origin) }) else { return }
        
        let thumbnailScaleFactor = 0.3
        let thumbnailWidth = max(200, min(image.size.width * thumbnailScaleFactor, 350))  // Minimum width of 200
        let thumbnailHeight = max(150, min(image.size.height * thumbnailScaleFactor, 500)) // Minimum height of 150
        let thumbnailSize = NSSize(width: thumbnailWidth, height: thumbnailHeight)
        let thumbnailOrigin = NSPoint(
            x: screen.frame.maxX - thumbnailSize.width - 20,
            y: screen.frame.minY + 20
        )
        
        let thumbnailView = ThumbnailView(image: image, overlayManager: self, screen: screen, origin: thumbnailOrigin, size: thumbnailSize)
        thumbnailWindow = NSWindow(
            contentRect: NSRect(origin: thumbnailOrigin, size: thumbnailSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        thumbnailWindow?.level = .statusBar
        thumbnailWindow?.isOpaque = false
        thumbnailWindow?.backgroundColor = .clear
        thumbnailWindow?.contentView = thumbnailView
        thumbnailWindow?.makeKeyAndOrderFront(nil)
    }
    
    func hideThumbnail() {
        if let window = thumbnailWindow {
            window.orderOut(nil)
            thumbnailWindow = nil
            NSApplication.shared.terminate(nil) // Close app after save or delete
        }
    }
    
    // MARK: - Overlay Visibility
    private func hideOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
    }
    
    /// Refreshes the `needsDisplay` flag on all overlay windows to trigger a redraw.
    private func refreshOverlays() {
        overlayWindows.forEach { $0.contentView?.needsDisplay = true }
    }
    
    // MARK: - Private Helpers
    
    /// Starts dragging either the rectangle or the menu.
    private func startDragging(rectangle: Bool = false, menu: Bool = false, at point: NSPoint) {
        draggingRectangle = rectangle
        draggingMenu = menu
        
        let xRect = rectangle ? self.rectangle.origin.x : menuRect.origin.x
        let yRect = rectangle ? self.rectangle.origin.y : menuRect.origin.y
        dragOffset = NSPoint(x: point.x - xRect, y: point.y - yRect)
    }
    
    /// Stops all dragging operations.
    private func stopDragging() {
        draggingRectangle = false
        draggingMenu = false
    }
    
    /// Clamps the rectangle or menuRect to stay within the bounds of all screens
    private func clampRectangleToScreens(rect: NSRect) -> NSRect {
        var clampedRect = rect
        let screens = NSScreen.screens.map { $0.frame }
        
        for screen in screens {
            if screen.intersects(clampedRect) {
                clampedRect.origin.x = max(clampedRect.origin.x, screen.minX)
                clampedRect.origin.y = max(clampedRect.origin.y, screen.minY)
                clampedRect.origin.x = min(clampedRect.origin.x, screen.maxX - clampedRect.width)
                clampedRect.origin.y = min(clampedRect.origin.y, screen.maxY - clampedRect.height)
                break
            }
        }
        return clampedRect
    }
    
    // MARK: - UserDefaults Persistence
    
    /// Save the rectangle's position and size to UserDefaults
    private func saveRectangle(_ rect: NSRect) {
        let frameDict = [
            "x": rect.origin.x,
            "y": rect.origin.y,
            "width": rect.size.width,
            "height": rect.size.height
        ]
        UserDefaults.standard.set(frameDict, forKey: Constants.rectangleKey)
    }
    
    /// Save the menu rectangle's position to UserDefaults
    private func saveMenuRect(_ rect: NSRect) {
        let frameDict = [
            "x": rect.origin.x,
            "y": rect.origin.y
        ]
        UserDefaults.standard.set(frameDict, forKey: Constants.menuRectKey)
    }
    
    /// Loads the rectangle's position and size from UserDefaults. Returns nil if loading fails.
    private static func loadRectangle() -> NSRect {
        guard let frameDict = UserDefaults.standard.dictionary(forKey: Constants.rectangleKey) as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return getDefaultRectangle()
        }
        
        let rectangle = NSRect(x: x, y: y, width: width, height: height)
        
        return isRectangleVisible(rectangle) ? rectangle : getDefaultRectangle()
    }
    
    /// Loads the menu rectangle's position from UserDefaults, falling back to 20px below the selection rectangle.
    private static func loadMenuRect(for rectangle: NSRect) -> NSRect {
        let menuWidth = Constants.Menu.Button.dragWidth + Constants.Menu.Button.cancelWidth + Constants.Menu.Button.optionsWidth + Constants.Menu.Button.captureWidth
        let menuHeight: CGFloat = 50
        let size = (menuWidth, menuHeight)
        
        if let frameDict = UserDefaults.standard.dictionary(forKey: Constants.menuRectKey) as? [String: CGFloat],
           let x = frameDict["x"],
           let y = frameDict["y"] {
            let menuRect = NSRect(x: x, y: y, width: menuWidth, height: menuHeight)
            return isRectangleVisible(menuRect) ? menuRect : getDefaultMenuRect(for: rectangle, size: size)
        }
        
        return getDefaultMenuRect(for: rectangle, size: size)
    }
    
    /// Checks if any part of the rectangle is visible on a screen.
    private static func isRectangleVisible(_ rect: NSRect) -> Bool {
        return NSScreen.screens.contains { screen in
            rect.intersects(screen.frame)
        }
    }
    
    private static func getDefaultRectangle() -> NSRect {
        let defaultWidth: CGFloat = Constants.SelectionRectangle.initialWidth
        let defaultHeight: CGFloat = Constants.SelectionRectangle.initialHeight
        
        guard let primaryScreen = NSScreen.main else {
            return NSRect(
                x: Constants.SelectionRectangle.initialX,
                y: Constants.SelectionRectangle.initialY,
                width: defaultWidth,
                height: defaultHeight
            )
        }
        
        let screenFrame = primaryScreen.visibleFrame
        
        let defaultX = screenFrame.midX - (defaultWidth / 2)
        let defaultY = screenFrame.midY - (defaultHeight / 2)
        
        return NSRect(x: defaultX, y: defaultY, width: defaultWidth, height: defaultHeight)
    }
    
    /// Returns the default menu rectangle position, 20px below the selection rectangle.
    private static func getDefaultMenuRect(for rectangle: NSRect, size: (CGFloat, CGFloat)) -> NSRect {
        let menuWidth = size.0
        let menuHeight = size.1
        let menuX = rectangle.midX - (menuWidth / 2) // Center horizontally below rectangle
        let menuY = rectangle.minY - menuHeight - 20 // 20px below rectangle
        
        return NSRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
    }
    
    // Reset rectangle and menu positions to defaults
    func resetPositions() {
        UserDefaults.standard.removeObject(forKey: Constants.rectangleKey)
        UserDefaults.standard.removeObject(forKey: Constants.menuRectKey)
        rectangle = Self.loadRectangle()
        menuRect = Self.loadMenuRect(for: rectangle)
        refreshOverlays()
    }
}

// Custom NSWindow subclass to allow borderless window to become key
class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true // Allow this window to become the key window
    }
}
