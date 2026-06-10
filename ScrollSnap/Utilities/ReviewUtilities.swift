//
//  ReviewUtilities.swift
//  ScrollSnap
//

import StoreKit

private let reviewCaptureThreshold = 3

@MainActor
func recordSuccessfulCaptureForReview() {
    guard hasAppStoreReceipt() else { return }

    let defaults = UserDefaults.standard
    let version = UpdateFeedbackManager.currentAppVersion

    synchronizeReviewState(for: version, defaults: defaults)

    let captureCount = defaults.integer(forKey: Constants.Review.successfulCaptureCountKey)
    defaults.set(captureCount + 1, forKey: Constants.Review.successfulCaptureCountKey)
}

@MainActor
func requestReviewIfEligible() async {
    guard hasAppStoreReceipt() else { return }
    guard !UpdateFeedbackManager().hasPendingUpgradeUI else { return }

    let defaults = UserDefaults.standard
    let version = UpdateFeedbackManager.currentAppVersion

    synchronizeReviewState(for: version, defaults: defaults)

    guard defaults.integer(forKey: Constants.Review.successfulCaptureCountKey) >= reviewCaptureThreshold else {
        return
    }

    guard defaults.string(forKey: Constants.Review.lastReviewAttemptVersionKey) != version else {
        return
    }

    defaults.set(version, forKey: Constants.Review.lastReviewAttemptVersionKey)
    SKStoreReviewController.requestReview()
    await Task.yield()
}

private func hasAppStoreReceipt() -> Bool {
    guard let receiptURL = Bundle.main.appStoreReceiptURL else {
        return false
    }

    return ["receipt", "sandboxReceipt"].contains(receiptURL.lastPathComponent) &&
        FileManager.default.fileExists(atPath: receiptURL.path)
}

private func synchronizeReviewState(for version: String, defaults: UserDefaults) {
    guard defaults.string(forKey: Constants.Review.captureCountVersionKey) != version else {
        return
    }

    defaults.set(version, forKey: Constants.Review.captureCountVersionKey)
    defaults.set(0, forKey: Constants.Review.successfulCaptureCountKey)
    defaults.removeObject(forKey: Constants.Review.lastReviewAttemptVersionKey)
}
