import AppKit
import XCTest

@MainActor
final class CaptureUITests: XCTestCase {
    private var fixture: XCUIApplication!
    private var captureApp: XCUIApplication?
    private var originalClipboard: [[(NSPasteboard.PasteboardType, Data)]] = []
    private var viewport: XCUIElement { fixture.scrollViews["baseline.viewport"] }
    private var status: XCUIElement { fixture.staticTexts["baseline.status"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let path = ProcessInfo.processInfo.environment["SCROLLSNAP_APP_PATH"] ?? ""
        if let identifier = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else {
                throw XCTSkip("Stop the existing ScrollSnap development build in Xcode before running this baseline.")
            }
        }
        fixture = XCUIApplication()
        fixture.launch()
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        XCTAssertTrue(status.waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        captureApp?.terminate()
        fixture?.terminate()
        let items = originalClipboard.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    func testSlowCapture() throws { try scriptedCapture(speed: "Slow") }
    func testFastCapture() throws { try scriptedCapture(speed: "Fast") }

    func testConversationCaptureAtNormalAndFastSpeeds() throws {
        fixture.terminate()
        fixture.launchArguments = ["-FixturePattern", "conversation"]
        fixture.launch()
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        let document = ConversationFixture.image()
        let expected = NSImage(cgImage: document, size: NSSize(width: document.width, height: document.height))
        let finalOffset = document.height - ConversationFixture.viewportHeight
        try launchCaptureApp()
        for speed in ["Normal", "Fast"] {
            if speed == "Fast" {
                fixture.buttons["Reset"].click()
                try reopenOverlay()
            }
            try startCapture()
            fixture.buttons[speed].click()
            waitUntil("Conversation reaches its end", timeout: 15) { self.statusText == "Done: \(finalOffset)" }
            let image = try finishCapture()
            attach(image, name: "conversation-\(speed)")
            XCTAssertEqual(image.size.height, CGFloat(document.height), accuracy: 1)
            let mismatch = try XCTUnwrap(ConversationFixture.maximumBandMismatch(image, expected: expected),
                                         "Cannot compare \(speed) capture: actual \(image.size), expected \(expected.size)")
            XCTAssertLessThanOrEqual(mismatch, 0.02,
                                     "\(speed): missing, duplicated, reordered, or corrupted conversation content")
            XCTAssertFalse(captureApp!.descendants(matching: .any).matching(identifier: "capture.incomplete.notice").firstMatch.exists)
        }
    }

    func testPinnedHeaderCapturePreservesBandsAndGradient() throws {
        for pattern in VerticalDetailFixture.allCases {
            fixture.terminate()
            fixture.launchArguments = ["-FixturePattern", pattern.rawValue]
            fixture.launch()
            XCTAssertTrue(viewport.waitForExistence(timeout: 10))
            waitUntil("Vertical fixture is ready", timeout: 5) { self.statusText == "Ready: 0" }
            let initial = normalized(viewport.screenshot().image)
            attach(initial, name: "\(pattern.rawValue)-initial")
            XCTAssertEqual(FixtureDocument.rows(in: initial), [1], "Only the fixed header contains a row marker")
            try launchCaptureApp()
            try startCapture()
            fixture.buttons["Normal"].click()
            waitUntil("Vertical fixture reaches its end", timeout: 5) { self.statusText == "Done: \(pattern.movement)" }
            let image = try finishCapture()
            attach(image, name: "\(pattern.rawValue)-actual")
            attach(pattern.expectedImage(), name: "\(pattern.rawValue)-expected")
            XCTAssertEqual(image.size.height, CGFloat(pattern.height), accuracy: 2)
            XCTAssertEqual(FixtureDocument.rows(in: image), [1], "The fixed header must appear once")
            XCTAssertEqual(try XCTUnwrap(pattern.bodyMismatchFraction(in: image)), 0,
                           "\(pattern.rawValue): missing, duplicated, or reordered body content")
            XCTAssertFalse(captureApp!.descendants(matching: .any).matching(identifier: "capture.incomplete.notice").firstMatch.exists)
            captureApp!.terminate()
            captureApp = nil
        }
    }

    private func scriptedCapture(speed: String) throws {
        try launchCaptureApp()
        try captureCompleteDocument(speed: speed, name: speed)
    }

    private func captureCompleteDocument(speed: String = "Normal", name: String) throws {
        try startCapture()
        fixture.buttons[speed].click()
        waitUntil("Fixture reaches its end", timeout: 25) { self.statusText == "Done: 2000" }
        let image = try finishCapture()
        attach(image, name: name)
        XCTAssertEqual(FixtureDocument.rows(in: image), Array(1...60), "\(name): missing or repeated rows")
        XCTAssertEqual(image.size.height, CGFloat(FixtureDocument.height), accuracy: 2, name)
    }

    func testNativeScrollPassesThroughOverlay() throws {
        // Calibrate the native scroll direction against the fixture before measuring the overlay.
        viewport.scroll(byDeltaX: 0, deltaY: -160)
        var delta: CGFloat = -160
        if offset == 0 { delta = 160; viewport.scroll(byDeltaX: 0, deltaY: delta) }
        XCTAssertGreaterThan(offset, 0, "Native fixture scrolling must work without ScrollSnap")
        fixture.buttons["Reset"].click()
        try launchCaptureApp()
        try startCapture()
        viewport.scroll(byDeltaX: 0, deltaY: delta)
        waitUntil("Native scrolling reaches the underlying document", timeout: 5) { self.offset > 0 }
        let top = offset
        let image = try finishCapture()
        attach(image, name: "native-scroll")
        let expected = FixtureDocument.image().cropping(to: CGRect(x: 0, y: 0, width: FixtureDocument.width,
                                                                   height: FixtureDocument.viewportHeight + top))!
        let expectedImage = NSImage(cgImage: expected, size: NSSize(width: FixtureDocument.width,
                                                                   height: FixtureDocument.viewportHeight + top))
        XCTAssertEqual(FixtureDocument.rows(in: image), FixtureDocument.rows(in: expectedImage))
    }

    func testNormalCapturesWithoutRestarting() throws {
        XCTAssertEqual(FixtureDocument.rows(in: normalized(viewport.screenshot().image)), Array(1...10))
        try launchCaptureApp()
        for iteration in 1...3 {
            if iteration > 1 {
                fixture.buttons["Reset"].click()
                try reopenOverlay()
            }
            try captureCompleteDocument(name: "session-\(iteration)")
        }
    }

    func testCancelThenCaptureAgain() throws {
        try launchCaptureApp()
        try startCapture()
        captureApp!.activate()
        captureApp!.typeKey(.escape, modifierFlags: [])
        waitUntil("Cancelled overlay closes", timeout: 10) { self.captureApp!.dialogs.count == 0 && self.captureApp!.windows.count == 0 }
        try reopenOverlay()
        try captureCompleteDocument(name: "after-cancellation")
    }

    func testIncompleteThumbnailRemainsInteractiveOnCaptureDisplay() throws {
        let primaryTop = try XCTUnwrap(NSScreen.screens.first).frame.maxY
        for screenIndex in 0..<min(2, NSScreen.screens.count) {
            fixture.terminate()
            fixture.launchArguments = ["-FixtureScreenIndex", String(screenIndex)]
            fixture.launch()
            XCTAssertTrue(viewport.waitForExistence(timeout: 10))
            try launchCaptureApp(destination: "Downloads")
            try startCapture()
            fixture.buttons["Unrelated"].click()
            waitUntil("Unrelated content is visible", timeout: 5) { self.statusText.hasPrefix("Replaced") }
            captureApp!.activate()
            captureApp!.typeKey(.return, modifierFlags: [])
            let notice = captureApp!.descendants(matching: .any).matching(identifier: "capture.incomplete.notice").firstMatch
            XCTAssertTrue(notice.waitForExistence(timeout: 10))
            let windows = captureApp!.dialogs.allElementsBoundByIndex + captureApp!.windows.allElementsBoundByIndex
            let thumbnail = try XCTUnwrap(windows.first { $0.frame.contains(notice.frame) })
            let visible = NSScreen.screens[screenIndex].visibleFrame
            let expected = CGRect(x: visible.minX, y: primaryTop - visible.maxY,
                                  width: visible.width, height: visible.height)
            XCTAssertTrue(expected.contains(thumbnail.frame), "Warning and thumbnail must stay on the capture display")
            attach(thumbnail.screenshot().image, name: "incomplete-thumbnail-display-\(screenIndex)")
            thumbnail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).rightClick()
            let delete = captureApp!.menus.menuItems.matching(identifier: "Delete").firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5), "Thumbnail must remain clickable without dismissing a modal")
            delete.click()
            waitUntil("Thumbnail closes", timeout: 5) { !notice.exists }
            captureApp!.terminate()
            captureApp = nil
        }
    }

    func testIncompleteClipboardNoticeAllowsAnotherCapture() throws {
        try launchCaptureApp()
        try startCapture()
        fixture.buttons["Unrelated"].click()
        waitUntil("Unrelated content is visible", timeout: 5) { self.statusText.hasPrefix("Replaced") }
        _ = try finishCapture()
        let notice = captureApp!.descendants(matching: .any).matching(identifier: "capture.incomplete.notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        fixture.buttons["Reset"].click()
        try reopenOverlay()
        XCTAssertFalse(notice.exists)
        try captureCompleteDocument(name: "after-incomplete-capture")
    }

    private var statusText: String { status.value as? String ?? status.label }
    private var offset: Int { Int(statusText.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0 }

    private func launchCaptureApp(destination: String = "Clipboard") throws {
        let path = ProcessInfo.processInfo.environment["SCROLLSNAP_APP_PATH"] ?? ""
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "CaptureBaseline", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Build the development app and supply SCROLLSNAP_APP_PATH"])
        }
        let frame = viewport.frame
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let bottom = screen.frame.maxY - frame.maxY
        let rect = try preferenceArgument(["x": Double(frame.minX), "y": Double(bottom),
                                           "width": Double(frame.width), "height": Double(frame.height)])
        let menu = try preferenceArgument(["x": Double(frame.minX), "y": Double(bottom + frame.height + 40)])
        let appURL = URL(fileURLWithPath: path)
        captureApp = XCUIApplication(url: appURL)
        let version = Bundle(url: URL(fileURLWithPath: path))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        captureApp!.launchArguments = ["-LastRectangleFrame", rect, "-LastMenuFrame", menu,
                                       "-SelectedDestination", destination, "-AppleLanguages", "(en)",
                                       "-SelectedAppLanguage", "en",
                                       "-UpdateFeedbackHandledFeedbackVersion", version,
                                       "-UpdateFeedbackLastSeenAppVersion", version]
        captureApp!.launch()
        waitUntil("Overlay or permission window appears", timeout: 10) {
            self.captureApp!.dialogs.firstMatch.exists || self.captureApp!.windows.firstMatch.exists
        }
        if captureApp!.windows["Screen Recording Required"].exists {
            throw XCTSkip("Blocked: grant Screen Recording to the development ScrollSnap app, then rerun. The test does not grant permissions.")
        }
    }

    private func preferenceArgument(_ values: [String: Double]) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        return String(data: data, encoding: .utf8)!
    }

    private func startCapture() throws {
        captureApp!.activate()
        captureApp!.typeKey(.return, modifierFlags: [])
        waitUntil("Capture border turns red", timeout: 10) { self.hasRedCaptureBorder() }
    }

    private func finishCapture() throws -> NSImage {
        let count = NSPasteboard.general.changeCount
        captureApp!.activate()
        captureApp!.typeKey(.return, modifierFlags: [])
        waitUntil("New PNG reaches the clipboard", timeout: 20) {
            NSPasteboard.general.changeCount != count && NSPasteboard.general.data(forType: .png) != nil
        }
        let data = try XCTUnwrap(NSPasteboard.general.data(forType: .png))
        return normalized(try XCTUnwrap(NSImage(data: data)))
    }

    private func reopenOverlay() throws {
        let path = ProcessInfo.processInfo.environment["SCROLLSNAP_APP_PATH"]!
        let url = URL(fileURLWithPath: path)
        let identifier = try XCTUnwrap(Bundle(url: url)?.bundleIdentifier)
        let pid = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first?.processIdentifier)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        let opened = expectation(description: "Existing app reopens its overlay")
        var reopenedApp: NSRunningApplication?
        var openError: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            reopenedApp = app
            openError = error
            opened.fulfill()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 10), .completed)
        XCTAssertNil(openError)
        XCTAssertEqual(try XCTUnwrap(reopenedApp).processIdentifier, pid, "Reopening must preserve the app process")
        XCTAssertTrue(captureApp!.dialogs.firstMatch.waitForExistence(timeout: 10))
    }

    private func hasRedCaptureBorder() -> Bool {
        guard let app = captureApp else { return false }
        guard let window = app.dialogs.allElementsBoundByIndex.first(where: { $0.frame.contains(viewport.frame) }) else { return false }
        let screenshot = window.screenshot().image
        guard let cg = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let scale = CGFloat(cg.width) / window.frame.width
        let x = Int((viewport.frame.minX - window.frame.minX) * scale)
        let y = Int((viewport.frame.midY - window.frame.minY) * scale)
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for xx in max(0, x - 4)...min(cg.width - 1, x + 4) {
            let index = min(cg.height - 1, max(0, y)) * context.bytesPerRow + xx * 4
            if pixels[index] > 200 && pixels[index + 1] < 80 && pixels[index + 2] < 80 { return true }
        }
        return false
    }

    private func normalized(_ image: NSImage) -> NSImage {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = viewport.frame.width
            image.size = NSSize(width: width, height: CGFloat(cg.height) * width / CGFloat(cg.width))
        }
        return image
    }

    private func waitUntil(_ description: String, timeout: TimeInterval, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, description)
    }

    private func attach(_ image: NSImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
