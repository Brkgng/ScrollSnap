//
//  ThumbnailView.swift
//  ScrollSnap
//

import AppKit

class ThumbnailView: NSView {
    // MARK: - Properties
    
    /// The screenshot image to display
    let image: NSImage
    /// Manager for overlay and thumbnail lifecycle
    private let overlayManager: OverlayManager
    /// Screen where the thumbnail is displayed
    private let screen: NSScreen
    /// Initial position of the thumbnail
    private var initialOrigin: NSPoint
    /// Initial width of the thumbnail
    private var initialWidth: CGFloat
    /// Timer for auto-saving after 15 seconds
    private var thumbnailTimer: Timer?
    /// Fire date of the timer for drag cancel checks
    private var timerFireDate: Date?
    
    /// State related to dragging interactions
    private struct DragState {
        var offset: NSPoint?        // Offset from mouse down to window origin
        var isDraggingRight: Bool   // Tracks rightward swipe
        var hasDragged: Bool        // Indicates any drag occurred
        var lastXPosition: CGFloat? // Last smoothed X position for swipe
        var initialMouseX: CGFloat? // Initial X position when mouse down
        var gestureCommitted: Bool  // Whether gesture type is determined
    }
    private var dragState = DragState(offset: nil, isDraggingRight: false, hasDragged: false, lastXPosition: nil, initialMouseX: nil, gestureCommitted: false)
    
    /// Threshold for movement before determining gesture intent (in points)
    private let gestureThreshold: CGFloat = 10.0
    
    // MARK: - Initialization
    init(image: NSImage, overlayManager: OverlayManager, screen: NSScreen, origin: NSPoint, size: NSSize) {
        self.image = image
        self.overlayManager = overlayManager
        self.screen = screen
        self.initialOrigin = origin
        self.initialWidth = size.width
        super.init(frame: NSRect(origin: .zero, size: size))
        
        setupTimer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.0)
        let borderPath = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        context.addPath(borderPath.cgPath)
        context.strokePath()
        
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 4
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.set()
    }
    
    // MARK: - Mouse Events
    /// Starts a drag by setting initial offset and position
    override func mouseDown(with event: NSEvent) {
        guard let window = overlayManager.thumbnailWindow else { return }
        dragState.offset = NSPoint(
            x: event.locationInWindow.x - window.frame.origin.x,
            y: event.locationInWindow.y - window.frame.origin.y
        )
        dragState.lastXPosition = window.frame.origin.x
        dragState.initialMouseX = event.locationInWindow.x
        dragState.gestureCommitted = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let dragOffset = dragState.offset,
              let window = overlayManager.thumbnailWindow,
              let initialMouseX = dragState.initialMouseX else { return }
        
        dragState.hasDragged = true
        
        let currentMouseX = event.locationInWindow.x
        let deltaX = currentMouseX - initialMouseX
        
        // If gesture not yet committed, check if we've moved enough to determine intent
        if !dragState.gestureCommitted {
            let movementDistance = abs(deltaX)
            
            // Not enough movement yet, wait for clearer intent
            if movementDistance < gestureThreshold {
                return
            }
            
            // Enough movement - determine gesture type based on direction
            if deltaX > 0 {
                // Rightward movement = swipe intent
                dragState.isDraggingRight = true
                dragState.gestureCommitted = true
            } else {
                // Leftward movement = drag intent
                dragState.isDraggingRight = false
                dragState.gestureCommitted = true
                // Start drag session immediately
                startDraggingSession(with: event)
                return
            }
        }
        
        // Execute the committed gesture
        if dragState.isDraggingRight {
            let newX = currentMouseX - dragOffset.x
            handleSwipeRightMovement(window: window, newX: newX)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        // Ensure window is available
        guard let window = overlayManager.thumbnailWindow else { return }
        
        // Only process if mouseDown occurred (offset set)
        if dragState.offset != nil {
            // Calculate movement from start to end
            let finalX = window.frame.origin.x
            let startX = dragState.lastXPosition ?? initialOrigin.x
            let distanceMoved = abs(finalX - startX)
            
            // Handle click or swipe based on drag state
            if !dragState.hasDragged && distanceMoved < Constants.Thumbnail.clickDistanceThreshold {
                handleClick()
            } else if dragState.isDraggingRight {
                let isNearInitial = abs(finalX - initialOrigin.x) <= Constants.Thumbnail.swipeDistanceThreshold
                if isNearInitial {
                    handleSwipeBack(window: window)
                } else {
                    handleSwipeRight(window: window)
                }
            }
        }
        
        // Reset interaction state
        resetDragState()
    }
    
    // MARK: - Mouse Event Handlers
    /// Handles a click on the thumbnail (no drag, minimal movement)
    private func handleClick() {
        // Stop timer, open image in Preview, and close app
        thumbnailTimer?.invalidate()
        saveImage(image, to: "Preview")
        overlayManager.thumbnailWindow?.orderOut(nil)
        NSApplication.shared.terminate(nil)
    }
    
    /// Handles swipe-right beyond threshold: animates off-screen, saves, and closes
    private func handleSwipeRight(window: NSWindow) {
        thumbnailTimer?.invalidate() // Prevent timer save during animation
        
        let targetX = screen.frame.maxX
        let currentWidth = window.frame.width
        
        // Animate thumbnail sliding off to the right
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.Thumbnail.swipeRightAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            NSAnimationContext.current.allowsImplicitAnimation = true
            let newWidth = max(0, currentWidth - (targetX - window.frame.origin.x))
            window.setFrame(NSRect(x: targetX - newWidth, y: window.frame.origin.y, width: newWidth, height: window.frame.height), display: true)
            window.alphaValue = 0.3
        } completionHandler: {
            self.overlayManager.thumbnailWindow?.orderOut(nil)
            self.saveAndClose()
        }
    }
    
    /// Handles swipe-back to initial position: animates return, keeps thumbnail active
    private func handleSwipeBack(window: NSWindow) {
        // Animate thumbnail back to starting position
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.Thumbnail.swipeBackAnimationDuration
            window.animator().setFrame(NSRect(x: self.initialOrigin.x, y: self.initialOrigin.y, width: self.initialWidth, height: window.frame.height), display: true)
            window.animator().alphaValue = 1.0
        }
    }
    
    /// Resets drag-related state after mouse up
    private func resetDragState() {
        dragState = DragState(offset: nil, isDraggingRight: false, hasDragged: false, lastXPosition: nil, initialMouseX: nil, gestureCommitted: false)
    }
    
    /// Handles rightward swipe movement, updating position and width
    private func handleSwipeRightMovement(window: NSWindow, newX: CGFloat) {
        // Smooth the X position (70% new, 30% old for fluid motion)
        let smoothedX = dragState.lastXPosition != nil ? (Constants.Thumbnail.swipeSmoothingNewFactor * newX + Constants.Thumbnail.swipeSmoothingOldFactor * dragState.lastXPosition!) : newX
        let smoothedRightEdge = smoothedX + initialWidth
        
        // Update position and width based on screen edge
        if smoothedRightEdge < screen.frame.maxX {
            // Within screen bounds: move with full width
            updateSwipeRightPosition(window: window, x: smoothedX, width: initialWidth)
        } else {
            // Past right edge: shrink width to fit screen
            let newWidth = max(0, screen.frame.maxX - smoothedX)
            updateSwipeRightPosition(window: window, x: smoothedX, width: newWidth)
            
            // If fully swiped off (width ≤ 0), save and close immediately
            if newWidth <= 0 {
                overlayManager.thumbnailWindow?.orderOut(nil)
                saveAndClose()
                return
            }
        }
        
        // Update last position for next smoothing iteration
        dragState.lastXPosition = smoothedX
    }
    
    /// Updates the thumbnail's position and width during swipe-right
    private func updateSwipeRightPosition(window: NSWindow, x: CGFloat, width: CGFloat) {
        window.setFrame(NSRect(x: x, y: initialOrigin.y, width: width, height: window.frame.height), display: true)
    }
    
    // MARK: - Right-Click Context Menu
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        
        menu.addItem(withTitle: "Save", action: #selector(saveImageAction), keyEquivalent: "")
        menu.addItem(withTitle: "Delete", action: #selector(deleteImage), keyEquivalent: "")
        menu.addItem(withTitle: "Close", action: #selector(closeThumbnail), keyEquivalent: "")
        
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc private func saveImageAction() {
        if let url = saveImage(image) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
        overlayManager.hideThumbnail()
    }
    
    @objc private func deleteImage() {
        overlayManager.hideThumbnail()
    }
    
    @objc private func closeThumbnail() {
        saveAndClose()
    }
    
    // MARK: - Helper Methods
    /// Sets up the 15-second timer for auto-saving the image
    private func setupTimer() {
        thumbnailTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.saveAndClose()
        }
        timerFireDate = thumbnailTimer?.fireDate
    }
    
    private func saveAndClose() {
        saveImage(image)
        overlayManager.hideThumbnail()
    }
    
    private func startDraggingSession(with event: NSEvent) {
        overlayManager.thumbnailWindow?.orderOut(nil)
        thumbnailTimer?.invalidate() // Prevent save during drag
        
        // Create pasteboard item on-demand when drag actually starts
        let item = NSPasteboardItem()
        
        // Add TIFF representation
        if let tiffData = image.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }
        
        // Add PNG representation
        if let pngData = image.pngData {
            item.setData(pngData, forType: .png)
        }
        
        // Create temp file only when dragging starts
        if let fileURL = saveImageToTemporaryFile(image) {
            item.setDataProvider(self, forTypes: [.fileURL])
            item.setString(fileURL.absoluteString, forType: .fileURL)
        }
        
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: image)
        
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: - NSDraggingSource
extension ThumbnailView: NSDraggingSource, NSPasteboardItemDataProvider {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            NSApplication.shared.terminate(nil)
        } else {
            handleDragCancel()
        }
    }
    
    /// Handles drag cancellation, restoring or saving based on timer expiration
    private func handleDragCancel() {
        let now = Date()
        if let fireDate = timerFireDate, fireDate < now {
            saveAndClose()
        } else {
            overlayManager.thumbnailWindow?.makeKeyAndOrderFront(nil)
            overlayManager.thumbnailWindow?.setFrame(NSRect(x: initialOrigin.x, y: initialOrigin.y, width: initialWidth, height: frame.height), display: true)
            overlayManager.thumbnailWindow?.alphaValue = 1.0
            if let fireDate = timerFireDate {
                let remainingTime = fireDate.timeIntervalSince(now)
                if remainingTime > 0 {
                    thumbnailTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                        self?.saveAndClose()
                    }
                }
            }
        }
    }
    
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .fileURL,
              let fileURLString = item.string(forType: .fileURL),
              let fileURL = URL(string: fileURLString) else { return }
        pasteboard?.writeObjects([fileURL as NSURL])
    }
    
}

// MARK: - NSImage Extension
extension NSImage {
    var pngData: Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
