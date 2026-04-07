//
//  SettingsView.swift
//  ScrollSnap
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    let onResetPositions: () -> Void
    let onAppear: () -> Void
    let onDisappear: () -> Void

    @AppStorage(AppLanguage.storageKey)
    private var selectedLanguageRawValue = AppLanguage.defaultValue.rawValue
    
    @State private var initialLanguageRawValue: String = ""

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

    private func openSupportEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "yasarberkergungor@gmail.com"
        
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ScrollSnap Feedback (v\(version))")
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAppStoreReviewPage() {
        guard let url = URL(string: "macappstore://apps.apple.com/app/id6744903723?action=write-review") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
    
    private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(AppText.general, systemImage: "gearshape")
                }
                
            aboutTab
                .tabItem {
                    Label(AppText.about, systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 270)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .navigationTitle(AppText.settingsWindowTitle)
        .onAppear {
            initialLanguageRawValue = selectedLanguageRawValue
            onAppear()
        }
        .onDisappear(perform: onDisappear)
        .onExitCommand {
            dismissWindow()
        }
    }
    
    private var generalTab: some View {
        Form {
            Section {
                Picker("\(AppText.language):", selection: selectedLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.localizedTitle)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                
                if selectedLanguageRawValue != initialLanguageRawValue && !initialLanguageRawValue.isEmpty {
                    Button(action: restartApp) {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(AppText.relaunchToApplyLanguageChanges)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 4)
                }
            }
            
            Section {
                Button(action: onResetPositions) {
                    HStack {
                        Text(AppText.resetSelectionAndMenuPositions)
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
    }
    
    private var aboutTab: some View {
        Form {
            VStack(spacing: 8) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ScrollSnap")
                    .font(.title2.bold())
                    
                if let versionText {
                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Section {
                Button(action: openSupportEmail) {
                    HStack {
                        Label(AppText.contactSupport, systemImage: "envelope")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: openAppStoreReviewPage) {
                    HStack {
                        Label(AppText.rateOnTheAppStore, systemImage: "star")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .foregroundColor(.secondary)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .formStyle(.grouped)
    }
}
