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
                onAppear: appDelegate.overlayManager.suspendFloatingWindowsForSettings,
                onDisappear: appDelegate.overlayManager.resumeFloatingWindowsAfterSettings
            )
        }
        .windowResizability(.contentSize)
    }
}
