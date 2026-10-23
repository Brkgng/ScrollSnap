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
            id: "printable-pdfs",
            symbolName: "doc.richtext",
            color: .green,
            titleKey: "whatsNew.highlight.printablePDFs.title",
            titleFallback: "Printable PDFs",
            messageKey: "whatsNew.highlight.printablePDFs.message",
            messageFallback: "Save long screenshots as multipage PDFs, ready to print on A4 or Letter paper."
        )
    ]
}
