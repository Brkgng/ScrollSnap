//
//  OverlayManager.swift
//  ScrollSnap
//

import SwiftUI

enum FloatingWindowSuspensionReason: Hashable {
    case settings
    case whatsNew
}

enum CaptureSessionState {
    case idle
    case selecting
    case capturing
    case finishing
    case thumbnail
}

@MainActor
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
    private var captureSessionID: UUID?
    private var thumbnailSessionID: UUID?
    private var captureTimer: Timer?
    private var scrollingCaptureSession: ScrollingCaptureSession?
    private var pointerMonitors: [Any] = []
    private var pointerPollTimer: Timer?
    private var isOverlayIgnoringMouseEvents = false
    private var optionsPopupRect: NSRect?
    var thumbnailWindow: NSWindow?
    private var suspendedWindowsState: SuspendedWindowsState?
    private var activeSuspensionReasons = Set<FloatingWindowSuspensionReason>()
    private(set) var sessionState: CaptureSessionState = .idle
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
    var canPresentOverlay: Bool {
        sessionState == .idle && activeSuspensionReasons.isEmpty
    }
    
    // MARK: - Initialization
    
    init() {
        let restoredRectangle = Self.loadRectangleRestore()

        /// Load the last saved rectangle position or use the default
        rectangle = restoredRectangle.rect
        
        /// Load the last saved menu position or position it 20px below the rectangle
        menuRect = Self.loadMenuRect(for: restoredRectangle)
    }
    
    // MARK: - Public API
    
    /// Presents a fresh overlay for the current display topology.
    @discardableResult
    func presentOverlay() -> Bool {
        guard canPresentOverlay else { return false }

        reconcileFramesWithCurrentScreens()
        rebuildOverlayWindows()
        sessionState = .selecting
        syncOverlayWindows()
        installPointerMonitors()
        updatePointerTransparency()
        return true
    }

    func dismissOverlay() {
        switch sessionState {
        case .selecting:
            hideOverlays()
            sessionState = .idle
        case .capturing:
            cancelScrollingCapture()
        case .idle, .finishing, .thumbnail:
            break
        }
    }

    private func rebuildOverlayWindows() {
        hideOverlays()
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
        guard isOverlayIgnoringMouseEvents != ignoresMouseEvents else { return }
        isOverlayIgnoringMouseEvents = ignoresMouseEvents
        overlayWindows.forEach { $0.ignoresMouseEvents = ignoresMouseEvents }
    }

    func suspendFloatingWindows(for reason: FloatingWindowSuspensionReason) {
        let insertedReason = activeSuspensionReasons.insert(reason).inserted
        guard insertedReason, activeSuspensionReasons.count == 1 else { return }

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

    func resumeFloatingWindows(for reason: FloatingWindowSuspensionReason) {
        guard activeSuspensionReasons.remove(reason) != nil else { return }
        guard activeSuspensionReasons.isEmpty else { return }
        guard let suspendedWindowsState else { return }

        if !suspendedWindowsState.visibleOverlayIndexes.isEmpty {
            syncOverlayWindows()
        }

        if suspendedWindowsState.wasThumbnailVisible {
            thumbnailWindow?.orderFrontRegardless()
            thumbnailWindow?.makeKey()
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

        switch sessionState {
        case .selecting:
            let sessionID = UUID()
            captureSessionID = sessionID
            sessionState = .capturing
            Task { [weak self] in
                await self?.startScrollingCapture(sessionID: sessionID)
            }
        case .capturing:
            guard let sessionID = captureSessionID,
                  isScrollingCaptureActive else { return }
            isScrollingCaptureActive = false
            sessionState = .finishing
            Task { [weak self] in
                await self?.stopScrollingCapture(sessionID: sessionID)
            }
        case .idle, .finishing, .thumbnail:
            break
        }
    }
    
    /// Stops the scrolling capture process and saves collected images.
    private func stopScrollingCapture(sessionID: UUID) async {
        guard captureSessionID == sessionID,
              sessionState == .finishing,
              let scrollingCaptureSession else { return }

        isScrollingCaptureActive = false
        invalidateCaptureTimer()
        hideOverlays()

        guard let finalImage = await scrollingCaptureSession.finish(),
              captureSessionID == sessionID else {
            guard captureSessionID == sessionID else { return }
            self.scrollingCaptureSession = nil
            captureSessionID = nil
            sessionState = .idle
            return
        }

        recordSuccessfulCaptureForReview()
        let selectedDestination = SaveDestination.current()
        self.scrollingCaptureSession = nil
        captureSessionID = nil

        switch selectedDestination.behavior {
        case .clipboard, .preview:
            _ = saveImage(finalImage)
            sessionState = .idle
        case .file:
            guard let thumbnailSessionID = showThumbnail(with: finalImage) else { return }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard self.thumbnailSessionID == thumbnailSessionID,
                  sessionState == .thumbnail,
                  thumbnailWindow?.isVisible == true else { return }

            await requestReviewIfEligible()
        }
    }
    
    /// Starts the scrolling capture process.
    private func startScrollingCapture(sessionID: UUID) async {
        guard captureSessionID == sessionID,
              sessionState == .capturing else { return }

        let captureRectangle = rectangle
        let screenshotSessionTask = Task { @MainActor in
            await ScreenshotCaptureSession(rectangle: captureRectangle)
        }
        let scrollingCaptureSession = ScrollingCaptureSession {
            guard let screenshotSession = await screenshotSessionTask.value else { return nil }
            return await screenshotSession.capture()
        }
        self.scrollingCaptureSession = scrollingCaptureSession
        isScrollingCaptureActive = true

        let didStart = await scrollingCaptureSession.start()

        guard captureSessionID == sessionID,
              isScrollingCaptureActive,
              sessionState == .capturing else {
            if captureSessionID == sessionID, sessionState == .finishing {
                return
            }
            await scrollingCaptureSession.cancel()
            if self.scrollingCaptureSession === scrollingCaptureSession {
                self.scrollingCaptureSession = nil
            }
            return
        }

        guard didStart else {
            isScrollingCaptureActive = false
            self.scrollingCaptureSession = nil
            captureSessionID = nil
            sessionState = .selecting
            refreshOverlays()
            return
        }

        // Allow mouse events to pass through during capture
        // so the underlying app can still be scrolled
        setOverlayIgnoresMouseEvents(true)

        setupCaptureTimer(sessionID: sessionID)
        refreshOverlays()
    }
    
    private func setupCaptureTimer(sessionID: UUID) {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.captureSessionID == sessionID,
                      self.isScrollingCaptureActive,
                      self.sessionState == .capturing else { return }

                self.scrollingCaptureSession?.requestFrame()
            }
        }
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelScrollingCapture() {
        guard sessionState == .capturing,
              captureSessionID != nil else { return }

        let scrollingCaptureSession = scrollingCaptureSession
        self.scrollingCaptureSession = nil
        captureSessionID = nil
        isScrollingCaptureActive = false
        invalidateCaptureTimer()
        setOverlayIgnoresMouseEvents(false)
        hideOverlays()

        Task { [weak self] in
            guard let self else { return }
            await scrollingCaptureSession?.cancel()
            guard self.sessionState == .capturing,
                  self.captureSessionID == nil else { return }
            self.sessionState = .idle
        }
    }
    
    private func invalidateCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    // MARK: - Thumbnail Management
    
    private func showThumbnail(with image: NSImage) -> UUID? {
        thumbnailSessionID = nil

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rectangle.origin) }) else {
            sessionState = .idle
            return nil
        }

        let sessionID = UUID()
        thumbnailSessionID = sessionID
        sessionState = .thumbnail
        
        let thumbnailScaleFactor = 0.3
        let thumbnailWidth = max(200, min(image.size.width * thumbnailScaleFactor, 350))  // Minimum width of 200
        let thumbnailHeight = max(150, min(image.size.height * thumbnailScaleFactor, 500)) // Minimum height of 150
        let thumbnailSize = NSSize(width: thumbnailWidth, height: thumbnailHeight)
        let thumbnailOrigin = NSPoint(
            x: screen.frame.maxX - thumbnailSize.width - 20,
            y: screen.frame.minY + 20
        )
        
        let thumbnailView = ThumbnailView(image: image, overlayManager: self, screen: screen, origin: thumbnailOrigin, size: thumbnailSize)
        thumbnailWindow = OverlayWindow(
            contentRect: NSRect(origin: thumbnailOrigin, size: thumbnailSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        thumbnailWindow?.level = .statusBar
        thumbnailWindow?.isOpaque = false
        thumbnailWindow?.backgroundColor = .clear
        thumbnailWindow?.collectionBehavior = Constants.Overlay.collectionBehavior
        thumbnailWindow?.hidesOnDeactivate = false
        thumbnailWindow?.contentView = thumbnailView
        thumbnailWindow?.orderFrontRegardless()
        thumbnailWindow?.makeKey()
        return sessionID
    }
    
    func hideThumbnail() {
        thumbnailSessionID = nil

        if let window = thumbnailWindow {
            window.orderOut(nil)
            thumbnailWindow = nil
        }
        sessionState = .idle
    }
    
    // MARK: - Overlay Visibility
    private func hideOverlays() {
        removePointerMonitors()
        optionsPopupRect = nil
        isOverlayIgnoringMouseEvents = false
        overlayWindows.forEach {
            $0.ignoresMouseEvents = false
            $0.orderOut(nil)
        }
    }

    // MARK: - Pointer Pass-Through

    /// Tracks the pointer so the overlay only intercepts clicks that belong to its own chrome.
    /// Everything else — the app being captured, the Dock, the menu bar — stays clickable.
    private func installPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }

        // Event monitors react instantly; the poll is a safety net for pointer movement they miss.
        let pollTimer = Timer(timeInterval: Constants.Overlay.pointerPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePointerTransparency()
            }
        }
        RunLoop.main.add(pollTimer, forMode: .common)
        pointerPollTimer = pollTimer

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp]

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.updatePointerTransparency()
            }
        }) {
            pointerMonitors.append(globalMonitor)
        }

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.updatePointerTransparency()
            return event
        }) {
            pointerMonitors.append(localMonitor)
        }
    }

    private func removePointerMonitors() {
        pointerPollTimer?.invalidate()
        pointerPollTimer = nil
        pointerMonitors.forEach { NSEvent.removeMonitor($0) }
        pointerMonitors.removeAll()
    }

    /// Lets the overlay window swallow the pointer only while it is over overlay chrome.
    private func updatePointerTransparency() {
        guard !overlayWindows.isEmpty,
              sessionState == .selecting || sessionState == .capturing else { return }

        // Never flip mid-gesture: a drag that started on the overlay has to keep receiving events.
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let isOverChrome = isPointOverOverlayChrome(NSEvent.mouseLocation)
        setOverlayIgnoresMouseEvents(!isOverChrome)

        if !isOverChrome {
            clearMenuHoverStates()
        }
    }

    private func isPointOverOverlayChrome(_ point: NSPoint) -> Bool {
        if let optionsPopupRect, optionsPopupRect.contains(point) {
            return true
        }

        if menuRect.contains(point) {
            return true
        }

        // While capturing, the selection has to pass scroll events through to the captured app.
        guard sessionState == .selecting else { return false }

        let margin = Constants.Overlay.pointerMargin
        return rectangle.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    /// Registers the options popup so it keeps receiving clicks while it extends past the menu.
    func setOptionsPopupRect(_ rect: NSRect?) {
        optionsPopupRect = rect
        updatePointerTransparency()
    }

    private func clearMenuHoverStates() {
        overlayWindows.forEach { ($0.contentView as? OverlayView)?.clearHoverState() }
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

    private func reconcileFramesWithCurrentScreens() {
        let screenFrames = NSScreen.screens.map(\.frame)
        guard !screenFrames.isEmpty else { return }

        if !screenFrames.contains(where: { $0.intersects(rectangle) }) {
            let restoredRectangle = Self.defaultRestoredRectangle(wasRepaired: true)
            rectangle = restoredRectangle.rect
            menuRect = Self.loadMenuRect(for: restoredRectangle)
            saveRectangle(rectangle)
            saveMenuRect(menuRect)
            return
        }

        rectangle = clampRectangleToScreens(rect: rectangle)
        if !screenFrames.contains(where: { $0.intersects(menuRect) }) {
            let screenFrame = screenFrames.first(where: { $0.intersects(rectangle) }) ?? screenFrames[0]
            menuRect = Self.clampRectOrigin(
                Self.getDefaultMenuRect(for: rectangle, size: (MenuBarLayout.totalWidth, MenuBarLayout.height)),
                to: screenFrame
            )
            saveMenuRect(menuRect)
        } else {
            menuRect = clampRectangleToScreens(rect: menuRect)
        }
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
