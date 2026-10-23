import AppKit
import AVFoundation
import XCTest
@testable import ScrollSnap

@MainActor
final class CaptureTutorialTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CaptureTutorialTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCaptionsFollowDemoActions() {
        XCTAssertEqual(CaptureTutorialStep.at(0), .selection)
        XCTAssertEqual(CaptureTutorialStep.at(4.49), .selection)
        XCTAssertEqual(CaptureTutorialStep.at(4.5), .scroll)
        XCTAssertEqual(CaptureTutorialStep.at(9.99), .scroll)
        XCTAssertEqual(CaptureTutorialStep.at(10), .save)
        XCTAssertEqual(CaptureTutorialStep.at(CaptureTutorialStep.duration), .save)
    }

    func testLocalizedMoviesAndPostersAreBundled() async throws {
        for locale in ["en", "de", "es", "fr", "ja", "ko", "tr", "zh-Hans"] {
            let movie = try XCTUnwrap(CaptureTutorialStep.resourceURL(extension: "mp4", localization: locale))
            let poster = try XCTUnwrap(CaptureTutorialStep.resourceURL(extension: "png", localization: locale))
            XCTAssertNotNil(NSImage(contentsOf: poster), locale)
            let asset = AVURLAsset(url: movie)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, CaptureTutorialStep.duration, accuracy: 0.05, locale)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            XCTAssertEqual(tracks.count, 1, locale)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertTrue(audio.isEmpty, locale)
        }
    }

    func testDemoShowsCaptureFrameOnlyDuringScrolling() async throws {
        let url = try XCTUnwrap(CaptureTutorialStep.resourceURL(extension: "mp4", localization: "en"))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var redPixelCounts: [Int] = []
        for seconds in [3.75, 7.0, 12.5] {
            let frame = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let image = NSBitmapImageRep(cgImage: frame.image)
            XCTAssertEqual(image.pixelsWide, 1600)
            XCTAssertEqual(image.pixelsHigh, 1040)
            var count = 0
            for y in stride(from: 0, to: image.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: image.pixelsWide, by: 4) {
                    let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if color.redComponent > 0.85 && color.greenComponent < 0.3 && color.blueComponent < 0.3 {
                        count += 1
                    }
                }
            }
            redPixelCounts.append(count)
        }
        XCTAssertLessThan(redPixelCounts[0], 100, "Selection uses the real white resize frame")
        XCTAssertGreaterThan(redPixelCounts[1], 500, "Scrolling keeps the real red capture frame visible")
        XCTAssertLessThan(redPixelCounts[2], 100, "Saving removes the frame and shows the combined result")
    }

    func testCompletedDemoLeavesClearPaddingBelowLastLine() async throws {
        for locale in ["en", "de", "es", "fr", "ja", "ko", "tr", "zh-Hans"] {
            let url = try XCTUnwrap(CaptureTutorialStep.resourceURL(extension: "mp4", localization: locale))
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let frame = try await generator.image(at: CMTime(seconds: 13, preferredTimescale: 600))
            let image = NSBitmapImageRep(cgImage: frame.image)
            // Locate the white result's lower edge in its left margin, away from text.
            let bottom = try XCTUnwrap((0..<image.pixelsHigh).reversed().first { y in
                guard let color = image.colorAt(x: 516, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.97
            }, locale)
            var darkPixels = 0
            for y in (bottom - 12)..<bottom {
                for x in stride(from: 540, to: 1060, by: 2) {
                    let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.94 {
                        darkPixels += 1
                    }
                }
            }
            XCTAssertEqual(darkPixels, 0, "\(locale): the final sentence must not touch the result's bottom edge")
        }
    }

    func testNewUserRemainsEligibleAcrossLaunchesWhileAwaitingPermission() {
        let state = CaptureTutorialState(defaults: defaults)
        let updates = UpdateFeedbackManager(defaults: defaults)
        XCTAssertFalse(updates.hasPreviousAppState)
        TutorialAppDelegate(defaults: defaults).recordLaunch(screenRecordingAlreadyAllowed: false)
        XCTAssertTrue(state.isPending, "Eligibility must be recorded before launch tracking")

        let relaunched = CaptureTutorialState(defaults: UserDefaults(suiteName: suiteName)!)
        TutorialAppDelegate(defaults: defaults).recordLaunch(screenRecordingAlreadyAllowed: true)
        XCTAssertTrue(relaunched.isPending)
    }

    func testTrackedUpgradeDoesNotBecomeEligibleAndKeepsWhatsNew() {
        let version = UpdateFeedbackManager.currentAppVersion
        defaults.set("2.9.0", forKey: Constants.UpdateFeedback.lastSeenAppVersionKey)
        let updates = UpdateFeedbackManager(defaults: defaults)
        let state = CaptureTutorialState(defaults: defaults)
        TutorialAppDelegate(defaults: defaults).recordLaunch(screenRecordingAlreadyAllowed: false)
        XCTAssertFalse(state.isPending)
        XCTAssertEqual(updates.pendingVersionToShow, version)
    }

    func testLegacyInstallMarkersSuppressAutomaticTutorial() {
        let keys = [
            Constants.rectangleKey, Constants.menuRectKey,
            Constants.Menu.Options.selectedDestinationKey,
            Constants.Review.successfulCaptureCountKey,
            Constants.Review.captureCountVersionKey,
            Constants.Review.lastReviewAttemptVersionKey,
            Constants.UpdateFeedback.pendingFeedbackVersionKey,
            Constants.UpdateFeedback.handledFeedbackVersionKey,
            Constants.showInDockKey, AppLanguage.storageKey,
            ScreenshotFormat.storageKey, PDFPaperSize.storageKey,
            "desktopBookmark", "documentsBookmark", "downloadsBookmark"
        ]
        for key in keys {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.set("legacy", forKey: key)
            let state = CaptureTutorialState(defaults: defaults)
            state.recordLaunch(isExistingUser: UpdateFeedbackManager(defaults: defaults).hasPreviousAppState)
            XCTAssertFalse(state.isPending, key)
        }
    }

    func testExistingPermissionGrantSuppressesTutorialWithoutOtherHistory() {
        let state = CaptureTutorialState(defaults: defaults)
        TutorialAppDelegate(defaults: defaults).recordLaunch(screenRecordingAlreadyAllowed: true)
        state.recordLaunch(isExistingUser: false)
        XCTAssertFalse(state.isPending)
    }

    func testDismissalSurvivesRelaunchAndUpgrade() {
        let state = CaptureTutorialState(defaults: defaults)
        state.recordLaunch(isExistingUser: false)
        state.dismiss()
        let relaunchedDefaults = UserDefaults(suiteName: suiteName)!
        UpdateFeedbackManager(defaults: relaunchedDefaults).recordLaunch(currentVersion: "4.0.0")
        let relaunched = CaptureTutorialState(defaults: relaunchedDefaults)
        relaunched.recordLaunch(isExistingUser: false)
        XCTAssertFalse(relaunched.isPending)
    }

    #if DEBUG
    func testFirstUseTestRearmsOnlyTutorialAndAllowsPersistentDismissal() {
        let state = CaptureTutorialState(defaults: defaults)
        state.dismiss()
        defaults.set("3.3.0", forKey: Constants.UpdateFeedback.lastSeenAppVersionKey)
        defaults.set("tr", forKey: AppLanguage.storageKey)

        state.prepareForFirstUseTest()
        state.recordLaunch(isExistingUser: true)
        XCTAssertTrue(state.isPending)
        XCTAssertEqual(defaults.string(forKey: Constants.UpdateFeedback.lastSeenAppVersionKey), "3.3.0")
        XCTAssertEqual(defaults.string(forKey: AppLanguage.storageKey), "tr")

        state.dismiss()
        let relaunched = CaptureTutorialState(defaults: UserDefaults(suiteName: suiteName)!)
        relaunched.recordLaunch(isExistingUser: true)
        XCTAssertFalse(relaunched.isPending)
    }
    #endif

    func testPermissionDenialDefersTutorialUntilGranted() async {
        CaptureTutorialState(defaults: defaults).recordLaunch(isExistingUser: false)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.permissionAllowed = false
        let denied = expectation(description: "Permission UI requested")
        delegate.onPermissionWindow = { denied.fulfill() }
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        await fulfillment(of: [denied], timeout: 2)
        XCTAssertNil(delegate.captureTutorialWindow)
        XCTAssertEqual(delegate.captureCount, 0)
        XCTAssertTrue(CaptureTutorialState(defaults: defaults).isPending)

        delegate.permissionAllowed = true
        let shown = expectation(description: "Tutorial shown after permission")
        delegate.onTutorialWindow = { shown.fulfill() }
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertNotNil(delegate.captureTutorialWindow)
        XCTAssertEqual(delegate.captureCount, 0)
        XCTAssertEqual(delegate.whatsNewChecks, 0)
        // Close without continuing into a real capture during test cleanup.
        delegate.onTutorialWindow = nil
        delegate.captureTutorialWindow?.close()
    }

    func testClosingAutomaticTutorialPersistsAndRechecksPermissionBeforeCapture() async {
        CaptureTutorialState(defaults: defaults).recordLaunch(isExistingUser: false)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.presentCaptureInterfaceAfterPermissionGranted()
        XCTAssertNotNil(delegate.captureTutorialWindow)
        XCTAssertFalse(delegate.overlayManager.canPresentOverlay)
        XCTAssertEqual(delegate.captureCount, 0)

        let captured = expectation(description: "Capture follows tutorial")
        delegate.onCapture = { captured.fulfill() }
        delegate.captureTutorialWindow?.close()
        await fulfillment(of: [captured], timeout: 2)
        XCTAssertNil(delegate.captureTutorialWindow)
        XCTAssertFalse(CaptureTutorialState(defaults: defaults).isPending)
        XCTAssertEqual(delegate.permissionChecks, 1)
        XCTAssertEqual(delegate.captureCount, 1)
        XCTAssertEqual(delegate.whatsNewChecks, 1)
        XCTAssertTrue(delegate.overlayManager.canPresentOverlay)
    }

    func testPermissionRevokedDuringTutorialReturnsToPermissionFlow() async {
        CaptureTutorialState(defaults: defaults).recordLaunch(isExistingUser: false)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.presentCaptureInterfaceAfterPermissionGranted()
        delegate.permissionAllowed = false
        let denied = expectation(description: "Permission checked again")
        delegate.onPermissionWindow = { denied.fulfill() }
        delegate.captureTutorialWindow?.close()
        await fulfillment(of: [denied], timeout: 2)
        XCTAssertEqual(delegate.captureCount, 0)
        XCTAssertFalse(CaptureTutorialState(defaults: defaults).isPending)
    }

    func testHelpReopensSameWindowAfterDismissalWithoutRequestingPermissionOrStartingCapture() {
        CaptureTutorialState(defaults: defaults).dismiss()
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.permissionAllowed = false
        delegate.showCaptureTutorial()
        let window = delegate.captureTutorialWindow
        XCTAssertNotNil(window)
        delegate.showCaptureTutorial()
        XCTAssertTrue(window === delegate.captureTutorialWindow)
        window?.close()
        XCTAssertTrue(delegate.overlayManager.canPresentOverlay)
        delegate.showCaptureTutorial()
        XCTAssertNotNil(delegate.captureTutorialWindow)
        XCTAssertFalse(window === delegate.captureTutorialWindow)
        XCTAssertEqual(delegate.permissionChecks, 0)
        XCTAssertEqual(delegate.captureCount, 0)
        XCTAssertFalse(CaptureTutorialState(defaults: defaults).isPending)
        delegate.captureTutorialWindow?.close()
    }

    func testHelpDoesNotConsumePendingWhatsNewOrSettingsSuspension() {
        let version = UpdateFeedbackManager.currentAppVersion
        defaults.set(version, forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.overlayManager.suspendFloatingWindows(for: .settings)
        delegate.showCaptureTutorial()
        delegate.captureTutorialWindow?.close()
        XCTAssertFalse(delegate.overlayManager.canPresentOverlay)
        XCTAssertEqual(UpdateFeedbackManager(defaults: defaults).pendingVersionToShow, version)
        delegate.overlayManager.resumeFloatingWindows(for: .settings)
        XCTAssertTrue(delegate.overlayManager.canPresentOverlay)
    }

    func testExistingUserGoesStraightToCaptureAndWhatsNew() {
        CaptureTutorialState(defaults: defaults).recordLaunch(isExistingUser: true)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.presentCaptureInterfaceAfterPermissionGranted()
        XCTAssertNil(delegate.captureTutorialWindow)
        XCTAssertEqual(delegate.captureCount, 1)
        XCTAssertEqual(delegate.whatsNewChecks, 1)
    }

    func testCaptureInvocationWhileTutorialIsOpenDoesNotBypassIt() async {
        CaptureTutorialState(defaults: defaults).recordLaunch(isExistingUser: false)
        let delegate = TutorialAppDelegate(defaults: defaults)
        delegate.presentCaptureInterfaceAfterPermissionGranted()
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        await Task.yield()
        XCTAssertEqual(delegate.permissionChecks, 0)
        XCTAssertEqual(delegate.captureCount, 0)
        delegate.captureTutorialWindow?.close()
    }
}

@MainActor
private final class TutorialAppDelegate: AppDelegate {
    var permissionAllowed = true
    var onPermissionWindow: (() -> Void)?
    var onTutorialWindow: (() -> Void)?
    var onCapture: (() -> Void)?
    private(set) var permissionChecks = 0
    private(set) var captureCount = 0
    private(set) var whatsNewChecks = 0

    override func screenRecordingAccessIsAllowed() async throws -> Bool {
        permissionChecks += 1
        return permissionAllowed
    }

    override func showScreenRecordingPermissionWindow() {
        onPermissionWindow?()
    }

    override func activateTutorialWindow(_ window: NSWindow) {
        // Build the actual native window offscreen, without activating the app or desktop input.
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.contentView?.frame.width, 700)
        XCTAssertGreaterThan(window.contentView?.frame.height ?? 0, 300)
        onTutorialWindow?()
    }

    override func presentCaptureOverlay() -> Bool {
        captureCount += 1
        onCapture?()
        return true
    }

    override func showWhatsNewWindowIfNeeded() {
        whatsNewChecks += 1
    }
}
