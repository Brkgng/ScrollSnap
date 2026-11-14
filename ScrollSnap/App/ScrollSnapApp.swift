//
//  ScrollSnapApp.swift
//  ScrollSnap
//

import SwiftUI

@main
struct ScrollSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView(
                loginItemManager: appDelegate.loginItemManager,
                onResetPositions: appDelegate.overlayManager.resetPositions,
                onShowCaptureTutorial: { appDelegate.showCaptureTutorial() },
                onAppear: {
                    appDelegate.overlayManager.suspendFloatingWindows(for: .settings)
                },
                onDisappear: {
                    appDelegate.overlayManager.resumeFloatingWindows(for: .settings)
                }
            )
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text(AppText.settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button(AppText.quitApp) {
                    appDelegate.quit()
                }
                .keyboardShortcut("q", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button(AppText.captureTutorialMenuTitle) {
                    appDelegate.showCaptureTutorial()
                }
            }
        }
    }
}
