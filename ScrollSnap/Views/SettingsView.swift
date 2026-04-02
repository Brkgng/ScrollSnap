//
//  SettingsView.swift
//  ScrollSnap
//

import SwiftUI

struct SettingsView: View {
    let onResetPositions: () -> Void
    let onAppear: () -> Void
    let onDisappear: () -> Void

    @AppStorage(AppLanguage.storageKey)
    private var selectedLanguageRawValue = AppLanguage.defaultValue.rawValue

    private var selectedLanguage: Binding<AppLanguage> {
        Binding(
            get: {
                AppLanguage(rawValue: selectedLanguageRawValue) ?? AppLanguage.defaultValue
            },
            set: { newValue in
                selectedLanguageRawValue = newValue.rawValue
            }
        )
    }

    private var versionText: String? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        return AppText.versionLabel(for: version)
    }

    var body: some View {
        VStack(spacing: 20) {
            Form {
                Picker("\(AppText.language):", selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.localizedTitle)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)

                Text(AppText.relaunchToApplyLanguageChanges)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, 4)

                Button(action: onResetPositions) {
                    Label(
                        AppText.resetSelectionAndMenuPositions,
                        systemImage: "arrow.counterclockwise"
                    )
                }
            }

            if let versionText {
                Text(versionText)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 380)
        .fixedSize()
        .navigationTitle(AppText.settingsWindowTitle)
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
}

#Preview {
    SettingsView(
        onResetPositions: {},
        onAppear: {},
        onDisappear: {}
    )
}
