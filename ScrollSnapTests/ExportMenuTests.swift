import AppKit
import XCTest
@testable import ScrollSnap

@MainActor
final class ExportMenuTests: XCTestCase {
    private var previousPreferences: [String: Any] = [:]
    private let preferenceKeys = [ScreenshotFormat.storageKey, PDFPaperSize.storageKey, SaveDestination.storageKey]

    override func setUp() {
        super.setUp()
        previousPreferences = Dictionary(uniqueKeysWithValues: preferenceKeys.compactMap { key in
            UserDefaults.standard.object(forKey: key).map { (key, $0) }
        })
        ScreenshotFormat.png.persist()
        PDFPaperSize.a4.persist()
    }

    override func tearDown() {
        for key in preferenceKeys {
            UserDefaults.standard.set(previousPreferences[key], forKey: key)
        }
        super.tearDown()
    }

    func testCaptureOptionsUpdatesSharedFormatAndPaperPreferences() throws {
        let manager = OverlayManager()
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let overlay = OverlayView(manager: manager, screenFrame: screen)
        let menu = MenuBarView(manager: manager, screenFrame: screen, overlayView: overlay)
        let menuRect = manager.getMenuRectangle()
        menu.handleMouseDown(at: NSPoint(
            x: menuRect.minX + MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth + MenuBarLayout.optionsWidth / 2,
            y: menuRect.midY
        ))
        var popup = menu.getOptionsPopupRect(for: menuRect)
        XCTAssertNil(menu.getOptionsPopupRect(for: .paperSize(.a4), in: popup))
        let pdf = try XCTUnwrap(menu.getOptionsPopupRect(for: .format(.pdf), in: popup))
        XCTAssertTrue(menu.handleOpenPopupMouseDown(at: NSPoint(x: pdf.midX, y: pdf.midY)))
        XCTAssertEqual(UserDefaults.standard.string(forKey: ScreenshotFormat.storageKey), "pdf")

        // Choosing PDF leaves Options open so the paper size can be chosen immediately.
        popup = menu.getOptionsPopupRect(for: menuRect)
        let letter = try XCTUnwrap(menu.getOptionsPopupRect(for: .paperSize(.letter), in: popup))
        XCTAssertTrue(menu.handleOpenPopupMouseDown(at: NSPoint(x: letter.midX, y: letter.midY)))
        XCTAssertEqual(PDFPaperSize.current(), .letter)
        XCTAssertEqual(ScreenshotFormat.current(), .pdf)
        XCTAssertFalse(manager.getIsScrollingCaptureActive())
    }

    func testCaptureOptionsTargetsFitAndDoNotOverlapAcrossDisplays() throws {
        let manager = OverlayManager()
        for screen in [
            NSRect(x: 0, y: 0, width: 800, height: 600),
            NSRect(x: 1440, y: 0, width: 1280, height: 720),
            NSRect(x: -1280, y: 200, width: 1280, height: 720)
        ] {
            let overlay = OverlayView(manager: manager, screenFrame: screen)
            let menu = MenuBarView(manager: manager, screenFrame: screen, overlayView: overlay)
            for format in ScreenshotFormat.allCases {
                format.persist()
                for menuOrigin in [screen.origin, NSPoint(x: screen.maxX - 150, y: screen.maxY - 50)] {
                    let popup = menu.getOptionsPopupRect(for: NSRect(origin: menuOrigin, size: NSSize(width: 350, height: 50)))
                    XCTAssertTrue(screen.contains(popup))
                    var targets = SaveDestination.allCases.map { MenuBarView.OptionsPopupTarget.destination($0) }
                        + ScreenshotFormat.allCases.map { .format($0) }
                        + [.reset, .settings, .quit]
                    if format == .pdf { targets += PDFPaperSize.allCases.map { .paperSize($0) } }
                    let rects = try targets.map { try XCTUnwrap(menu.getOptionsPopupRect(for: $0, in: popup)) }
                    for (index, rect) in rects.enumerated() {
                        XCTAssertTrue(popup.contains(rect))
                        for other in rects.dropFirst(index + 1) {
                            XCTAssertFalse(rect.intersects(other), "Overlapping targets in \(format) Options")
                        }
                    }
                }
            }
        }
    }

    func testThumbnailCommandsOverrideOnlyTheCurrentSave() throws {
        ScreenshotFormat.pdf.persist()
        PDFPaperSize.letter.persist()
        let image = NSImage(size: NSSize(width: 10, height: 10))
        var calls: [(ScreenshotFormat?, PDFPaperSize?)] = []
        let manager = OverlayManager()
        let thumbnail = try makeThumbnail(manager: manager, image: image) { savedImage, format, paper in
            XCTAssertTrue(savedImage === image)
            calls.append((format, paper))
            return nil
        }
        let menu = thumbnail.makeContextMenu()
        menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { $0.title == AppText.save }))
        menu.performActionForItem(at: try XCTUnwrap(menu.items.firstIndex { $0.title == AppText.saveAsPNG }))
        let papers = try XCTUnwrap(menu.items.first { $0.title == AppText.saveAsPDF }?.submenu)
        XCTAssertEqual(papers.items.map(\.title), PDFPaperSize.allCases.map(\.localizedTitle))
        for index in papers.items.indices { papers.performActionForItem(at: index) }

        XCTAssertEqual(calls.count, 4)
        guard calls.count == 4 else { return }
        XCTAssertNil(calls[0].0)
        XCTAssertNil(calls[0].1)
        XCTAssertEqual(calls[1].0, .png)
        XCTAssertNil(calls[1].1)
        XCTAssertEqual(calls[2].0, .pdf)
        XCTAssertEqual(calls[2].1, .a4)
        XCTAssertEqual(calls[3].0, .pdf)
        XCTAssertEqual(calls[3].1, .letter)
        XCTAssertEqual(ScreenshotFormat.current(), .pdf)
        XCTAssertEqual(PDFPaperSize.current(), .letter)
    }

    func testPopupClickDoesNotReachCaptureOnMouseUp() throws {
        let manager = CaptureCountingOverlayManager()
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let overlay = OverlayView(manager: manager, screenFrame: screen)
        let window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = overlay
        let geometry = MenuBarView(manager: manager, screenFrame: screen, overlayView: overlay)
        let bar = manager.getMenuRectangle()
        let optionsPoint = NSPoint(
            x: bar.minX + MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth + MenuBarLayout.optionsWidth / 2,
            y: bar.midY
        )
        let captureRect = NSRect(
            x: bar.minX + MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth + MenuBarLayout.optionsWidth,
            y: bar.minY, width: MenuBarLayout.captureWidth, height: bar.height
        )
        func click(_ point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                if type == .leftMouseDown { overlay.mouseDown(with: event) }
                else { overlay.mouseUp(with: event) }
            }
        }

        // PNG moves the popup; selecting paper closes it. Both releases must stay consumed.
        for target in [MenuBarView.OptionsPopupTarget.format(.png), .paperSize(.a4)] {
            ScreenshotFormat.pdf.persist()
            PDFPaperSize.letter.persist()
            try click(optionsPoint)
            let popup = geometry.getOptionsPopupRect(for: bar)
            let choice = try XCTUnwrap(geometry.getOptionsPopupRect(for: target, in: popup))
            let overlap = choice.intersection(captureRect)
            XCTAssertFalse(overlap.isEmpty, "The regression requires the popup choice to overlap Capture")
            guard !overlap.isEmpty else { return }
            let previousCount = manager.captureCount
            try click(NSPoint(x: overlap.midX, y: overlap.midY))
            XCTAssertEqual(manager.captureCount, previousCount)

            try click(NSPoint(x: 10, y: 10)) // Dismiss Options if format selection left it open.
            try click(NSPoint(x: captureRect.midX, y: captureRect.midY))
            XCTAssertEqual(manager.captureCount, previousCount + 1, "An ordinary Capture click must still work")
        }
    }

    func testCapturingOptionsKeepsMouseEventsUntilPopupDismisses() throws {
        let manager = CapturingInputOverlayManager()
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 1200)
        let overlay = OverlayView(manager: manager, screenFrame: screen)
        let window = NSWindow(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = overlay
        let geometry = MenuBarView(manager: manager, screenFrame: screen, overlayView: overlay)
        let bar = manager.getMenuRectangle()
        let optionsPoint = NSPoint(
            x: bar.minX + MenuBarLayout.dragWidth + MenuBarLayout.cancelWidth + MenuBarLayout.optionsWidth / 2,
            y: bar.midY
        )

        func hoverMenu(_ entered: Bool) throws {
            let area = try XCTUnwrap(overlay.trackingAreas.first { $0.userInfo?["type"] as? String == "menu" })
            let trackingEvent = MenuTrackingEvent(area: area)
            if entered { overlay.mouseEntered(with: trackingEvent) }
            else { overlay.mouseExited(with: trackingEvent) }
        }

        func click(_ point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                if type == .leftMouseDown { overlay.mouseDown(with: event) }
                else { overlay.mouseUp(with: event) }
            }
        }

        func openOptions() throws {
            try hoverMenu(true)
            XCTAssertFalse(manager.ignoresMouseEvents)
            try click(optionsPoint)
            try hoverMenu(false)
            XCTAssertFalse(manager.ignoresMouseEvents, "Crossing the gap into Options must keep clicks enabled")
        }

        try openOptions()
        var popup = geometry.getOptionsPopupRect(for: bar)
        let destination = try XCTUnwrap(geometry.getOptionsPopupRect(for: .destination(.clipboard), in: popup))
        SaveDestination.downloads.persist()
        try click(NSPoint(x: destination.midX, y: destination.midY))
        XCTAssertEqual(SaveDestination.current(), .clipboard)
        XCTAssertTrue(manager.ignoresMouseEvents, "Choosing a destination restores scrolling")

        try openOptions()
        popup = geometry.getOptionsPopupRect(for: bar)
        let pdf = try XCTUnwrap(geometry.getOptionsPopupRect(for: .format(.pdf), in: popup))
        try click(NSPoint(x: pdf.midX, y: pdf.midY))
        XCTAssertEqual(ScreenshotFormat.current(), .pdf)
        XCTAssertFalse(manager.ignoresMouseEvents, "Format changes keep Options interactive")
        popup = geometry.getOptionsPopupRect(for: bar)
        let paper = try XCTUnwrap(geometry.getOptionsPopupRect(for: .paperSize(.letter), in: popup))
        try click(NSPoint(x: paper.midX, y: paper.midY))
        XCTAssertEqual(PDFPaperSize.current(), .letter)
        XCTAssertTrue(manager.ignoresMouseEvents, "Choosing paper size restores scrolling")

        try openOptions()
        try click(NSPoint(x: 10, y: 10))
        XCTAssertTrue(manager.ignoresMouseEvents, "Dismissing Options outside restores scrolling")

        try openOptions()
        try hoverMenu(true)
        try click(optionsPoint)
        XCTAssertFalse(manager.ignoresMouseEvents, "Closing Options over the toolbar keeps its buttons clickable")
        try hoverMenu(false)
        XCTAssertTrue(manager.ignoresMouseEvents)
        XCTAssertEqual(manager.captureCount, 0)
    }

    func testThumbnailTimerPausesDuringMenuAndResumesAfterCancellation() throws {
        let manager = OverlayManager()
        let thumbnail = try makeThumbnail(manager: manager) { _, _, _ in
            XCTFail("Opening or cancelling a menu must not save the image")
            return nil
        }
        let window = NSWindow(contentRect: thumbnail.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = thumbnail
        manager.thumbnailWindow = window
        let originalTimer = try XCTUnwrap(thumbnail.thumbnailTimer)
        thumbnail.withPausedAutoSave {
            XCTAssertFalse(originalTimer.isValid)
        }
        let resumedTimer = try XCTUnwrap(thumbnail.thumbnailTimer)
        XCTAssertFalse(originalTimer === resumedTimer)
        XCTAssertTrue(resumedTimer.isValid)
        XCTAssertGreaterThan(resumedTimer.fireDate.timeIntervalSinceNow, 14)
        manager.hideThumbnail()
    }

    func testThumbnailTimerDoesNotResumeAfterMenuClosesTheCapture() throws {
        let manager = OverlayManager()
        let thumbnail = try makeThumbnail(manager: manager) { _, _, _ in nil }
        let window = NSWindow(contentRect: thumbnail.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = thumbnail
        manager.thumbnailWindow = window
        thumbnail.withPausedAutoSave {
            manager.hideThumbnail()
        }
        XCTAssertFalse(try XCTUnwrap(thumbnail.thumbnailTimer).isValid)
    }

    private func makeThumbnail(
        manager: OverlayManager,
        image: NSImage = NSImage(size: NSSize(width: 10, height: 10)),
        save: @escaping (NSImage, ScreenshotFormat?, PDFPaperSize?) -> URL?
    ) throws -> ThumbnailView {
        ThumbnailView(
            image: image, overlayManager: manager, screen: try XCTUnwrap(NSScreen.main),
            origin: .zero, size: NSSize(width: 200, height: 150), save: save
        )
    }
}

@MainActor
private class CaptureCountingOverlayManager: OverlayManager {
    var captureCount = 0

    override func getMenuRectangle() -> NSRect {
        NSRect(x: 40, y: 350, width: MenuBarLayout.totalWidth, height: 50)
    }

    override func captureScreenshot() {
        captureCount += 1
    }
}

@MainActor
private final class CapturingInputOverlayManager: CaptureCountingOverlayManager {
    private(set) var ignoresMouseEvents = true

    override func getIsScrollingCaptureActive() -> Bool { true }

    override func setOverlayIgnoresMouseEvents(_ ignoresMouseEvents: Bool) {
        self.ignoresMouseEvents = ignoresMouseEvents
    }
}

private final class MenuTrackingEvent: NSEvent {
    private let area: NSTrackingArea

    init(area: NSTrackingArea) {
        self.area = area
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var trackingArea: NSTrackingArea? { area }
}
