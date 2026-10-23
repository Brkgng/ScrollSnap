import AppKit
import ScreenCaptureKit
import XCTest
@testable import ScrollSnap

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {
    func testGrantedPreflightDoesNotRequestAccess() async throws {
        let allowed = try await checkScreenRecordingPermission(preflight: { true }) {
            XCTFail("Existing access must not trigger another request")
        }
        XCTAssertTrue(allowed)
    }

    func testCaptureAPISuccessOverridesNegativePreflight() async throws {
        let allowed = try await checkScreenRecordingPermission(preflight: { false }) {}
        XCTAssertTrue(allowed)
    }

    func testExplicitDenialReturnsFalse() async throws {
        let allowed = try await checkScreenRecordingPermission(preflight: { false }) {
            throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        }
        XCTAssertFalse(allowed)
    }

    func testCaptureServiceFailureIsNotReportedAsPermissionDenial() async {
        await assertCheckThrows(NSError(domain: SCStreamErrorDomain, code: -3802))
    }

    func testUnrelatedErrorWithSameCodeIsNotReportedAsPermissionDenial() async {
        await assertCheckThrows(NSError(domain: "OtherService", code: SCStreamError.Code.userDeclined.rawValue))
    }

    func testWaitsForCaptureAPIResultBeforeReportingAccess() async throws {
        var accessContinuation: CheckedContinuation<Void, Error>?
        let started = expectation(description: "Access request started")
        var finished = false
        let check = Task { @MainActor in
            let allowed = try await checkScreenRecordingPermission(preflight: { false }) {
                try await withCheckedThrowingContinuation { continuation in
                    accessContinuation = continuation
                    started.fulfill()
                }
            }
            finished = true
            return allowed
        }

        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(finished, "The pending system request must not be treated as a denial")
        accessContinuation?.resume()
        let allowed = try await check.value
        XCTAssertTrue(allowed)
    }

    func testServiceFailurePresentsLocalizedAlertAndRetriesBeforeQuitting() async {
        let didQuit = expectation(description: "Quit selected after retry")
        let delegate = FailingPermissionAppDelegate(responses: [.alertFirstButtonReturn, .alertSecondButtonReturn], didQuit: didQuit)
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        await fulfillment(of: [didQuit], timeout: 2)

        XCTAssertEqual(delegate.checkCount, 2, "Try Again must perform a fresh access check")
        XCTAssertEqual(delegate.alerts.count, 2)
        for alert in delegate.alerts {
            XCTAssertEqual(alert.messageText, AppText.screenRecordingAccessCheckFailed)
            XCTAssertEqual(alert.informativeText, AppText.screenRecordingAccessCheckRetryMessage)
            XCTAssertEqual(alert.buttons.map(\.title), [AppText.tryAgain, AppText.quit])
        }
    }

    func testQuitFromServiceFailureDoesNotRetry() async {
        let didQuit = expectation(description: "Quit selected")
        let delegate = FailingPermissionAppDelegate(responses: [.alertSecondButtonReturn], didQuit: didQuit)
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        await fulfillment(of: [didQuit], timeout: 2)
        XCTAssertEqual(delegate.checkCount, 1)
        XCTAssertEqual(delegate.alerts.count, 1)
    }

    private func assertCheckThrows(_ expected: NSError) async {
        do {
            _ = try await checkScreenRecordingPermission(preflight: { false }) { throw expected }
            XCTFail("A service error must remain distinguishable from missing permission")
        } catch {
            XCTAssertEqual(error as NSError, expected)
        }
    }
}

@MainActor
private final class FailingPermissionAppDelegate: AppDelegate {
    private var responses: [NSApplication.ModalResponse]
    private let didQuit: XCTestExpectation
    private(set) var checkCount = 0
    private(set) var alerts: [NSAlert] = []

    init(responses: [NSApplication.ModalResponse], didQuit: XCTestExpectation) {
        self.responses = responses
        self.didQuit = didQuit
        super.init()
    }

    override func screenRecordingAccessIsAllowed() async throws -> Bool {
        checkCount += 1
        throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.failedToStart.rawValue)
    }

    override func presentScreenRecordingAccessError(_ alert: NSAlert) -> NSApplication.ModalResponse {
        alerts.append(alert)
        guard !responses.isEmpty else {
            XCTFail("Unexpected extra error alert")
            return .alertSecondButtonReturn
        }
        return responses.removeFirst()
    }

    override func quit() {
        didQuit.fulfill()
    }
}
