//
//  ScreenRecordingPermissionView.swift
//  ScrollSnap
//

import SwiftUI

struct ScreenRecordingPermissionView: View {
    let openSystemSettings: () -> Void
    let checkAgain: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(AppText.screenRecordingPermissionTitle)
                    .font(.title3.bold())

                Text(AppText.screenRecordingPermissionMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(AppText.quit) {
                    quit()
                }

                Spacer()

                Button(AppText.checkAgain) {
                    checkAgain()
                }

                Button(AppText.openSystemSettings) {
                    openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct ScreenRecordingPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenRecordingPermissionView(
            openSystemSettings: {},
            checkAgain: {},
            quit: {}
        )
    }
}
