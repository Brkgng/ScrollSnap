//
//  AppDelegate.swift
//  ScrollSnap
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayManager = OverlayManager()
    private var settingsWindowController: SettingsWindowController?
    private var permissionWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        
        Task {
            let hasPermission = await checkScreenRecordingPermission()
            await MainActor.run {
                if hasPermission {
                    // Setup overlays only if permission is granted
                    overlayManager.setupOverlays()
                } else {
                    self.showPermissionRequestWindow()
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
    
    private func showPermissionRequestWindow() {
        let permissionView = PermissionRequestView()
        let hostingController = NSHostingController(rootView: permissionView)
        
        permissionWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        permissionWindow?.center()
        permissionWindow?.contentViewController = hostingController
        permissionWindow?.title = "Screen Recording Permission"
        permissionWindow?.level = .floating
        permissionWindow?.makeKeyAndOrderFront(nil)
    }
}
