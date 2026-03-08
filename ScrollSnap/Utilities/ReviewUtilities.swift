//
//  ReviewUtilities.swift
//  ScrollSnap
//

import StoreKit

@MainActor
func requestReviewIfEligible() async {
    guard !UserDefaults.standard.bool(forKey: Constants.Review.hasRequestedInitialReviewKey) else {
        return
    }

    let hasAppStoreReceipt: Bool
    if let receiptURL = Bundle.main.appStoreReceiptURL {
        hasAppStoreReceipt = ["receipt", "sandboxReceipt"].contains(receiptURL.lastPathComponent) &&
            FileManager.default.fileExists(atPath: receiptURL.path)
    } else {
        hasAppStoreReceipt = false
    }
    
    guard hasAppStoreReceipt else { return }
    
    UserDefaults.standard.set(true, forKey: Constants.Review.hasRequestedInitialReviewKey)
    SKStoreReviewController.requestReview()
    await Task.yield()
}
