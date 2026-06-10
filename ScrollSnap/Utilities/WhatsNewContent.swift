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
            id: "sticky-header-support",
            symbolName: "macwindow.on.rectangle",
            color: .blue,
            titleKey: "whatsNew.highlight.stickyHeader.title",
            titleFallback: "Sticky Header Support",
            messageKey: "whatsNew.highlight.stickyHeader.message",
            messageFallback: "Scrolling captures now support pages with fixed navigation bars and sticky headers."
        ),
        WhatsNewHighlight(
            id: "animated-content-support",
            symbolName: "play.square.stack",
            color: .green,
            titleKey: "whatsNew.highlight.animatedContent.title",
            titleFallback: "Animated Content Support",
            messageKey: "whatsNew.highlight.animatedContent.message",
            messageFallback: "Capture pages with GIFs, video previews, and moving elements with smarter stitching built for dynamic content."
        ),
        WhatsNewHighlight(
            id: "fullscreen-spaces-support",
            symbolName: "arrow.up.left.and.arrow.down.right",
            color: .orange,
            titleKey: "whatsNew.highlight.fullscreenSpaces.title",
            titleFallback: "Fullscreen & Spaces Support",
            messageKey: "whatsNew.highlight.fullscreenSpaces.message",
            messageFallback: "Capture overlays and thumbnail controls now work across fullscreen apps and macOS Spaces."
        )
    ]
}
