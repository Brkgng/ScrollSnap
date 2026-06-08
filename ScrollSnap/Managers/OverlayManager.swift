//
//  OverlayManager.swift
//  ScrollSnap
//

import SwiftUI

class OverlayManager {
    private struct RestoredRect {
        let rect: NSRect
        let screenFrame: NSRect
        let wasRepaired: Bool
    }

    private struct SuspendedWindowsState {
        let visibleOverlayIndexes: Set<Int>
        let wasThumbnailVisible: Bool
    }
    
    // MARK: - Properties
    
    private var rectangle: NSRect
    private var menuRect: NSRect
    private var draggingRectangle = false
    private var draggingMenu = false
    private var dragOffset: NSPoint = .zero
    private var overlayWindows: [NSWindow] = []
    private var isScrollingCaptureActive = false
    private var isTimerCaptureInFlight = false
    private var captureTimer: Timer?
    private let stitchingManager = StitchingManager()
    var thumbnailWindow: NSWindow?
    private var suspendedWindowsState: SuspendedWindowsState?
    
    // MARK: - Initialization
    
    init() {
        let restoredRectangle = Self.loadRectangleRestore()

        /// Load the last saved rectangle position or use the default
        rectangle = restoredRectangle.rect
        
        /// Load the last saved menu position or position it 20px below the rectangle
        menuRect = Self.loadMenuRect(for: restoredRectangle)
    }
    
    // MARK: - Public API
    
    /// Sets up overlays on all available screens.
    func setupOverlays() {
        overlayWindows = NSScreen.screens.map { screen in
            let overlayWindow = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            overlayWindow.level = Constants.Overlay.windowLevel
            overlayWindow.isOpaque = false
            overlayWindow.backgroundColor = .clear
            overlayWindow.collectionBehavior = Constants.Overlay.collectionBehavior
            overlayWindow.hidesOnDeactivate = false
            overlayWindow.hasShadow = false
            
            let overlayView = OverlayView(manager: self, screenFrame: screen.frame)
            overlayWindow.contentView = overlayView
            
            return overlayWindow
        }

        syncOverlayWindows()
    }
    
    /// Updates the rectangle and persists it to UserDefaults. Refreshes all overlays.
    func updateRectangle(to newRect: NSRect) {
        let oldRect = self.rectangle
        rectangle = clampRectangleToScreens(rect: newRect)
        saveRectangle(rectangle)

        syncOverlayWindows()
        refreshOverlays(oldFrame: oldRect, newFrame: rectangle, includesDimensionLabel: true)
    }
    
    /// Updates the menu rectangle. Refreshes all overlays.
    func updateMenuRect(to newRect: NSRect) {
        let oldRect = self.menuRect
        let clampedRect = clampRectangleToScreens(rect: newRect)
        menuRect = clampedRect
        saveMenuRect(menuRect)
        syncOverlayWindows()
        refreshOverlays(oldFrame: oldRect, newFrame: menuRect)
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
    
    func setOverlayIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        overlayWindows.forEach { $0.ignoresMouseEvents = ignoresMouseEvents }
    }

    func suspendFloatingWindowsForSettings() {
        guard suspendedWindowsState == nil else { return }

        let visibleOverlayIndexes = Set(
            overlayWindows.enumerated().compactMap { index, window in
                window.isVisible ? index : nil
            }
        )
        let wasThumbnailVisible = thumbnailWindow?.isVisible == true

        suspendedWindowsState = SuspendedWindowsState(
            visibleOverlayIndexes: visibleOverlayIndexes,
            wasThumbnailVisible: wasThumbnailVisible
        )

        for index in visibleOverlayIndexes {
            overlayWindows[index].orderOut(nil)
        }

        if wasThumbnailVisible {
            thumbnailWindow?.orderOut(nil)
        }
    }

    func resumeFloatingWindowsAfterSettings() {
        guard let suspendedWindowsState else { return }

        if !suspendedWindowsState.visibleOverlayIndexes.isEmpty {
            syncOverlayWindows()
        }

        if suspendedWindowsState.wasThumbnailVisible {
            thumbnailWindow?.orderFront(nil)
        }

        self.suspendedWindowsState = nil
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
        guard !overlayWindows.isEmpty else { return }

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
        
        // Perform UI updates on the main thread first
        await MainActor.run {
            invalidateCaptureTimer()
            hideOverlays()
        }
        
        // Asynchronously wait for the stitching to complete in the background.
        // This frees up the main thread, keeping the app responsive.
        if let finalImage = await stitchingManager.stopStitching() {
            await recordSuccessfulCaptureForReview()

            let selectedDestination = await MainActor.run {
                SaveDestination.current()
            }
            
            switch selectedDestination.behavior {
            case .clipboard, .preview:
                await MainActor.run {
                    _ = saveImage(finalImage)
                }
            case .file:
                await MainActor.run {
                    showThumbnail(with: finalImage)
                }
                try? await Task.sleep(for: .seconds(1))
                await requestReviewIfEligible()
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
            // Allow mouse events to pass through during capture
            // so the underlying app can still be scrolled
            setOverlayIgnoresMouseEvents(true)
            
            setupCaptureTimer()
            refreshOverlays()
        }
    }
    
    private func setupCaptureTimer() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.isScrollingCaptureActive,
                  !self.isTimerCaptureInFlight else { return }
            
            self.isTimerCaptureInFlight = true
            
            Task {
                await self.handleTimerCapture()
                await MainActor.run {
                    self.isTimerCaptureInFlight = false
                }
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
        isTimerCaptureInFlight = false
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
            suspendedWindowsState = nil
            NSApplication.shared.terminate(nil) // Close app after save or delete
        }
    }
    
    // MARK: - Overlay Visibility
    private func hideOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
    }
    
    /// Refreshes overlays. If oldFrame and newFrame are provided, it invalidates only those regions.
    /// Otherwise, it falls back to a full redraw.
    private func refreshOverlays(oldFrame: NSRect? = nil, newFrame: NSRect? = nil, includesDimensionLabel: Bool = false) {
        if let oldFrame = oldFrame, let newFrame = newFrame {
            // Smart redraw logic
            let framesToUpdate = [oldFrame, newFrame]
            for window in overlayWindows {
                guard let view = window.contentView else { continue }
                let screenFrame = window.frame
                
                for frame in framesToUpdate {
                    // Check if the frame is on this screen
                    if screenFrame.intersects(frame) {
                        let dirtyRect: NSRect
                        if let overlayView = view as? OverlayView {
                            dirtyRect = overlayView.dirtyRect(forGlobalRect: frame, includesDimensionLabel: includesDimensionLabel)
                        } else {
                            let localRect = NSRect(
                                x: frame.origin.x - screenFrame.origin.x,
                                y: frame.origin.y - screenFrame.origin.y,
                                width: frame.width,
                                height: frame.height
                            )
                            dirtyRect = localRect.insetBy(dx: -10, dy: -10)
                        }
                        
                        if !dirtyRect.isEmpty {
                            view.setNeedsDisplay(dirtyRect)
                        }
                    }
                }
            }
        } else {
            // Fallback to full redraw for operations that affect everything
            overlayWindows.forEach { $0.contentView?.needsDisplay = true }
        }
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
    private static func loadRectangleRestore() -> RestoredRect {
        guard let frameDict = UserDefaults.standard.dictionary(forKey: Constants.rectangleKey) as? [String: CGFloat],
              let x = frameDict["x"],
              let y = frameDict["y"],
              let width = frameDict["width"],
              let height = frameDict["height"] else {
            return defaultRestoredRectangle()
        }
        
        let rectangle = NSRect(x: x, y: y, width: width, height: height)
        return normalizeRestoredRect(rectangle, wasSaved: true) ?? defaultRestoredRectangle(wasRepaired: true)
    }
    
    /// Loads the menu rectangle's position from UserDefaults, falling back to 20px below the selection rectangle.
    private static func loadMenuRect(for restoredRectangle: RestoredRect) -> NSRect {
        let menuWidth = MenuBarLayout.totalWidth
        let menuHeight = MenuBarLayout.height
        let size = (menuWidth, menuHeight)

        if restoredRectangle.wasRepaired {
            return normalizedDefaultMenuRect(for: restoredRectangle, size: size)
        }
        
        if let frameDict = UserDefaults.standard.dictionary(forKey: Constants.menuRectKey) as? [String: CGFloat],
           let x = frameDict["x"],
           let y = frameDict["y"] {
            let menuRect = NSRect(x: x, y: y, width: menuWidth, height: menuHeight)
            return normalizeRestoredRect(menuRect, wasSaved: true)?.rect ?? normalizedDefaultMenuRect(for: restoredRectangle, size: size)
        }
        
        return normalizedDefaultMenuRect(for: restoredRectangle, size: size)
    }
    
    private static func normalizeRestoredRect(_ rect: NSRect, wasSaved: Bool) -> RestoredRect? {
        if let screen = screenContainingOrigin(of: rect) {
            return RestoredRect(rect: rect, screenFrame: screen.frame, wasRepaired: false)
        }
        
        guard let screen = NSScreen.screens.first(where: { rect.intersects($0.frame) }) else {
            return nil
        }
        
        return RestoredRect(
            rect: clampRectOrigin(rect, to: screen.frame),
            screenFrame: screen.frame,
            wasRepaired: wasSaved
        )
    }
    
    private static func screenContainingOrigin(of rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(rect.origin) }
    }
    
    private static func clampRectOrigin(_ rect: NSRect, to screenFrame: NSRect) -> NSRect {
        let maxX = max(screenFrame.minX, screenFrame.maxX - rect.width)
        let maxY = max(screenFrame.minY, screenFrame.maxY - rect.height)
        
        return NSRect(
            x: min(max(rect.minX, screenFrame.minX), maxX),
            y: min(max(rect.minY, screenFrame.minY), maxY),
            width: rect.width,
            height: rect.height
        )
    }

    private static func defaultRestoredRectangle(wasRepaired: Bool = false) -> RestoredRect {
        let defaultRect = getDefaultRectangle()
        let screenFrame = screenContainingOrigin(of: defaultRect)?.frame ?? NSScreen.main?.frame ?? defaultRect

        return RestoredRect(rect: defaultRect, screenFrame: screenFrame, wasRepaired: wasRepaired)
    }

    private static func normalizedDefaultMenuRect(for restoredRectangle: RestoredRect, size: (CGFloat, CGFloat)) -> NSRect {
        let menuRect = getDefaultMenuRect(for: restoredRectangle.rect, size: size)
        return clampRectOrigin(menuRect, to: restoredRectangle.screenFrame)
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
        let restoredRectangle = Self.loadRectangleRestore()
        rectangle = restoredRectangle.rect
        menuRect = Self.loadMenuRect(for: restoredRectangle)
        if suspendedWindowsState == nil {
            syncOverlayWindows()
        }
        refreshOverlays()
    }

    private func syncOverlayWindows() {
        guard !overlayWindows.isEmpty else { return }

        overlayWindows.forEach { $0.orderFrontRegardless() }

        if let rectangleWindow = overlayWindows.first(where: { $0.frame.contains(rectangle.origin) }) {
            rectangleWindow.makeKey()
        }
    }
}

// Custom NSPanel subclass to allow the borderless overlay to become key without activating the app.
class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}
