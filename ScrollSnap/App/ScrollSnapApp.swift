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
                onResetPositions: appDelegate.overlayManager.resetPositions,
                onAppear: {
                    appDelegate.overlayManager.suspendFloatingWindows(for: .settings)
                },
                onDisappear: {
                    appDelegate.overlayManager.resumeFloatingWindows(for: .settings)
                }
            )
        }
        .windowResizability(.contentSize)
    }
}
