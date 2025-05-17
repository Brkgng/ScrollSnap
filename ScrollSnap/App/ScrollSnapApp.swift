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
            ContentView()
        }
    }
}
