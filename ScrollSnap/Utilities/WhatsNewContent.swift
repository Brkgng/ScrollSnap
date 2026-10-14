//
//  WhatsNewContent.swift
//  ScrollSnap
//

import SwiftUI

struct WhatsNewHighlight: Identifiable {
    let id: String
    let symbolName: String
    let color: Color
    let titleKey: String
    let titleFallback: String
    let messageKey: String
    let messageFallback: String

    var title: String {
        LocalizationResolver.string(titleKey, fallback: titleFallback)
    }

    var message: String {
        LocalizationResolver.string(messageKey, fallback: messageFallback)
    }
}

enum WhatsNewContent {
    static let currentHighlights: [WhatsNewHighlight] = [
        WhatsNewHighlight(
            id: "capture-reliability",
            symbolName: "checkmark.seal",
            color: .green,
            titleKey: "whatsNew.highlight.captureReliability.title",
            titleFallback: "More Reliable Scrolling Captures",
            messageKey: "whatsNew.highlight.captureReliability.message",
            messageFallback: "Improved stitching for faster scrolling, sticky headers, and changes in scroll direction."
        ),
        WhatsNewHighlight(
            id: "dock-access",
            symbolName: "macwindow",
            color: .blue,
            titleKey: "whatsNew.highlight.dockAccess.title",
            titleFallback: "ScrollSnap in Your Dock",
            messageKey: "whatsNew.highlight.dockAccess.message",
            messageFallback: "Switch to ScrollSnap with ⌘Tab to bring up the capture interface. Control Dock visibility in Settings."
        ),
        WhatsNewHighlight(
            id: "sharper-screenshots",
            symbolName: "viewfinder",
            color: .purple,
            titleKey: "whatsNew.highlight.sharperScreenshots.title",
            titleFallback: "Sharper Screenshots",
            messageKey: "whatsNew.highlight.sharperScreenshots.message",
            messageFallback: "Fixed an issue that could make text and fine details look blurry in some capture areas."
        ),
        WhatsNewHighlight(
            id: "incomplete-capture",
            symbolName: "exclamationmark.triangle",
            color: .orange,
            titleKey: "whatsNew.highlight.incompleteCapture.title",
            titleFallback: "Know When Something’s Missing",
            messageKey: "whatsNew.highlight.incompleteCapture.message",
            messageFallback: "ScrollSnap now warns you when a capture may be incomplete. Your captured image remains available."
        )
    ]
}
