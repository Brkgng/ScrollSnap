//
//  AppDelegate.swift
//  ScrollSnap
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayManager = OverlayManager()
    private var settingsWindowController: SettingsWindowController?
    private var localKeyEventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        
        cleanupOldTemporaryFiles()
        installLocalKeyEventMonitor()
        
        Task { @MainActor in
            if hasScreenRecordingPermission() {
                overlayManager.setupOverlays()
                return
            }

            _ = requestScreenRecordingPermission()

            if hasScreenRecordingPermission() {
                overlayManager.setupOverlays()
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyEventMonitor {
            NSEvent.removeMonitor(localKeyEventMonitor)
            self.localKeyEventMonitor = nil
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
    
    private func installLocalKeyEventMonitor() {
        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
        }
    }
    
    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        if isPreferencesShortcut(event) {
            showSettingsWindow()
            return nil
        }
        
        if isCaptureToggleEvent(event), event.window is OverlayWindow {
            overlayManager.captureScreenshot()
            return nil
        }
        
        if isEscapeEvent(event) {
            NSApplication.shared.terminate(self)
            return nil
        }
        
        return event
    }
    
    private func isPreferencesShortcut(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == ","
    }
    
    private func isCaptureToggleEvent(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        return event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}"
    }
    
    private func isEscapeEvent(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == "\u{1B}"
    }
    
    // MARK: - Temporary File Cleanup
    
    /// Cleans up ScrollSnap temporary files older than the specified retention period
    private func cleanupOldTemporaryFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory
        let retentionDays = 7 // Files older than this will be deleted
        
        do {
            let tempContents = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
                options: .skipsHiddenFiles
            )
            
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
            
            for fileURL in tempContents {
                // Only process files that match ScrollSnap's naming pattern
                guard fileURL.lastPathComponent.hasPrefix("Screenshot ") &&
                      fileURL.pathExtension == "png" else {
                    continue
                }
                
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
                    
                    // Ensure it's a regular file
                    guard resourceValues.isRegularFile == true else { continue }
                    
                    // Check if file is older than cutoff date
                    if let creationDate = resourceValues.creationDate,
                       creationDate < cutoffDate {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                } catch {
                    print("Failed to process temp file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            print("Failed to clean up temporary files: \(error.localizedDescription)")
        }
    }
}
