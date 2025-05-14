//
//  AppDelegate.swift
//  ScrollSnap
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayManager = OverlayManager()
    private var settingsWindowController: SettingsWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.setIsVisible(false)
        }
        
        setupMainMenu()
        
        // Check permission on launch
        Task {
            let hasPermission = await checkScreenRecordingPermission()
            await MainActor.run {
                if hasPermission {
                    // Setup overlays only if permission is granted
                    overlayManager.setupOverlays()
                } else {
                    showPermissionDeniedAlert()
                }
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.keyCode == 43 { // Command + ,
                self.showSettingsWindow()
                return nil
            }
            if event.keyCode == 53 { // Escape
                NSApplication.shared.terminate(self)
                return nil
            }
            return event
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem(title: "ScrollSnap", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "ScrollSnap")
        appMenu.addItem(withTitle: "About ScrollSnap", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit ScrollSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(overlayManager: overlayManager)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "ScrollSnap needs screen recording permission to capture screenshots. \n\nPlease enable it in System Preferences > Security & Privacy > Screen Recording, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { // Quit
            NSApplication.shared.terminate(self)
        }
    }
}
