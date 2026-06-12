//
//  WhatsNewView.swift
//  ScrollSnap
//

import SwiftUI

struct WhatsNewView: View {
    let version: String
    let highlights: [WhatsNewHighlight]
    let reportProblem: () -> Void
    let sendFeedback: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            highlightsList
            footer
        }
        .frame(width: 520)
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizationResolver.string(
                    "whatsNew.title",
                    fallback: "What's New in ScrollSnap"
                ))
                .font(.title2.bold())

                Text(String(
                    format: LocalizationResolver.string(
                        "whatsNew.versionSubtitle",
                        fallback: "Version %@"
                    ),
                    version
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var highlightsList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(highlights) { highlight in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: highlight.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(highlight.color.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(highlight.title)
                            .font(.headline)

                        Text(highlight.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(LocalizationResolver.string(
                "whatsNew.reportProblem",
                fallback: "Report a Problem"
            ), action: reportProblem)

            Button(LocalizationResolver.string(
                "whatsNew.sendFeedback",
                fallback: "Send Feedback"
            ), action: sendFeedback)

            Spacer()

            Button(LocalizationResolver.string(
                "whatsNew.gotIt",
                fallback: "Got it"
            ), action: dismiss)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    WhatsNewView(
        version: "2.6.0",
        highlights: WhatsNewContent.currentHighlights,
        reportProblem: {},
        sendFeedback: {},
        dismiss: {}
    )
}
