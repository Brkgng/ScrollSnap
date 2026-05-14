//
//  AppDelegate.swift
//  ScrollSnap
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let overlayManager = OverlayManager()
    private var localKeyEventMonitor: Any?
    private var screenRecordingPermissionWindow: NSWindow?
    private var didSetupOverlays = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        cleanupOldTemporaryFiles()
        installLocalKeyEventMonitor()
        
        Task { @MainActor in
            handleScreenRecordingPermissionOnLaunch()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyEventMonitor {
            NSEvent.removeMonitor(localKeyEventMonitor)
            self.localKeyEventMonitor = nil
        }
    }
    
    private func installLocalKeyEventMonitor() {
        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
        }
    }
    
    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        if isCaptureToggleEvent(event), event.window is OverlayWindow {
            overlayManager.captureScreenshot()
            return nil
        }
        
        if isEscapeEvent(event), event.window is OverlayWindow {
            NSApplication.shared.terminate(self)
            return nil
        }
        
        return event
    }
    
    private func isCaptureToggleEvent(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        return event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\u{3}"
    }
    
    private func isEscapeEvent(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == "\u{1B}"
    }

    // MARK: - Screen Recording Permission

    @MainActor
    private func handleScreenRecordingPermissionOnLaunch() {
        guard !setupOverlaysIfScreenRecordingIsAllowed() else { return }

        _ = requestScreenRecordingPermission()

        if !setupOverlaysIfScreenRecordingIsAllowed() {
            showScreenRecordingPermissionWindow()
        }
    }

    @MainActor
    @discardableResult
    private func setupOverlaysIfScreenRecordingIsAllowed() -> Bool {
        guard hasScreenRecordingPermission() else { return false }

        screenRecordingPermissionWindow?.close()
        screenRecordingPermissionWindow = nil

        guard !didSetupOverlays else { return true }
        didSetupOverlays = true
        overlayManager.setupOverlays()
        return true
    }

    @MainActor
    private func showScreenRecordingPermissionWindow() {
        if let screenRecordingPermissionWindow {
            screenRecordingPermissionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let permissionView = ScreenRecordingPermissionView(
            openSystemSettings: { [weak self] in
                self?.openScreenRecordingSettings()
            },
            checkAgain: { [weak self] in
                self?.checkScreenRecordingPermissionAgain()
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.screenRecordingPermissionTitle
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: permissionView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        screenRecordingPermissionWindow = window
    }

    @MainActor
    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func checkScreenRecordingPermissionAgain() {
        if !setupOverlaysIfScreenRecordingIsAllowed() {
            _ = requestScreenRecordingPermission()
            _ = setupOverlaysIfScreenRecordingIsAllowed()
        }
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
                guard AppText.supportedScreenshotFilenamePrefixes.contains(where: {
                    fileURL.lastPathComponent.hasPrefix("\($0) ")
                }) &&
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
