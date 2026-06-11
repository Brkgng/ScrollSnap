//
//  UpdateFeedbackManager.swift
//  ScrollSnap
//

import Foundation

struct UpdateFeedbackManager {
    private let defaults: UserDefaults
    private let firstTrackedUpgradeVersion = "3.0.0"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var pendingVersionToShow: String? {
        guard let pendingVersion = defaults.string(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey),
              pendingVersion == Self.currentAppVersion,
              defaults.string(forKey: Constants.UpdateFeedback.handledFeedbackVersionKey) != pendingVersion else {
            return nil
        }

        return pendingVersion
    }

    var hasPendingUpgradeUI: Bool {
        pendingVersionToShow != nil
    }

    func recordLaunch(currentVersion: String) {
        guard let lastSeenVersion = defaults.string(forKey: Constants.UpdateFeedback.lastSeenAppVersionKey) else {
            if currentVersion == firstTrackedUpgradeVersion,
               hasLegacyAppState,
               defaults.string(forKey: Constants.UpdateFeedback.handledFeedbackVersionKey) != currentVersion {
                defaults.set(currentVersion, forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
            }

            defaults.set(currentVersion, forKey: Constants.UpdateFeedback.lastSeenAppVersionKey)
            return
        }

        guard lastSeenVersion != currentVersion else { return }

        if let pendingVersion = defaults.string(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey),
           pendingVersion != currentVersion {
            defaults.removeObject(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
        }

        if isMajorOrMinorUpdate(from: lastSeenVersion, to: currentVersion),
           defaults.string(forKey: Constants.UpdateFeedback.handledFeedbackVersionKey) != currentVersion {
            defaults.set(currentVersion, forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
        } else if defaults.string(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey) == currentVersion {
            defaults.removeObject(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
        }

        defaults.set(currentVersion, forKey: Constants.UpdateFeedback.lastSeenAppVersionKey)
    }

    private var hasLegacyAppState: Bool {
        let legacyKeys = [
            Constants.rectangleKey,
            Constants.menuRectKey,
            Constants.Menu.Options.selectedDestinationKey,
            Constants.Review.successfulCaptureCountKey,
            Constants.Review.captureCountVersionKey,
            Constants.Review.lastReviewAttemptVersionKey
        ]

        return legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    func markHandled(version: String) {
        defaults.set(version, forKey: Constants.UpdateFeedback.handledFeedbackVersionKey)

        if defaults.string(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey) == version {
            defaults.removeObject(forKey: Constants.UpdateFeedback.pendingFeedbackVersionKey)
        }
    }

    private func isMajorOrMinorUpdate(from previousVersion: String, to currentVersion: String) -> Bool {
        guard let previous = SemanticVersion(previousVersion),
              let current = SemanticVersion(currentVersion) else {
            return false
        }

        if current.major > previous.major {
            return true
        }

        return current.major == previous.major && current.minor > previous.minor
    }
}

private struct SemanticVersion {
    let major: Int
    let minor: Int

    init?(_ version: String) {
        let parts = version.split(separator: ".")
        guard parts.count >= 2,
              let major = Self.numberPrefix(in: parts[0]),
              let minor = Self.numberPrefix(in: parts[1]) else {
            return nil
        }

        self.major = major
        self.minor = minor
    }

    private static func numberPrefix(in part: Substring) -> Int? {
        let digits = part.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
