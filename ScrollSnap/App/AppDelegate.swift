//
//  AppDelegate.swift
//  ScrollSnap
//

import SwiftUI
import KeyboardShortcuts

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let overlayManager = OverlayManager()
    let loginItemManager = LoginItemManager()
    private let updateFeedbackManager = UpdateFeedbackManager()
    private var localKeyEventMonitor: Any?
    private var shortcutTask: Task<Void, Never>?
    private var screenRecordingPermissionWindow: NSWindow?
    private var whatsNewWindow: NSWindow?
    private var whatsNewWindowVersion: String?
    private var isLoginLaunch = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        updateFeedbackManager.recordLaunch(currentVersion: UpdateFeedbackManager.currentAppVersion)
        cleanupOldTemporaryFiles()
        installLocalKeyEventMonitor()
        installGlobalShortcutHandler()
        overlayManager.openSettings = { [weak self] in self?.openSettings() }
        overlayManager.quit = { [weak self] in self?.quit() }

        isLoginLaunch = isLoginLaunch
            || ProcessInfo.processInfo.arguments.contains("--launch-at-login")
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !isLoginLaunch else { return }
            handleScreenRecordingPermissionOnLaunch()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: {
            $0.scheme == "com.berkergungor.scrollsnap.login"
                && $0.host == "launch-at-login"
        }) {
            isLoginLaunch = true
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let localKeyEventMonitor {
            NSEvent.removeMonitor(localKeyEventMonitor)
            self.localKeyEventMonitor = nil
        }
        shortcutTask?.cancel()
        shortcutTask = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            presentCaptureInterface()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === whatsNewWindow else { return }

        if let whatsNewWindowVersion {
            updateFeedbackManager.markHandled(version: whatsNewWindowVersion)
        }

        whatsNewWindow = nil
        whatsNewWindowVersion = nil
        overlayManager.resumeFloatingWindows(for: .whatsNew)
    }
    
    private func installLocalKeyEventMonitor() {
        localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
        }
    }
    
    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers == "q",
           event.window is OverlayWindow {
            quit()
            return nil
        }

        if isCaptureToggleEvent(event), event.window is OverlayWindow {
            overlayManager.captureScreenshot()
            return nil
        }
        
        if isEscapeEvent(event), event.window is OverlayWindow {
            overlayManager.dismissOverlay()
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

    private func installGlobalShortcutHandler() {
        shortcutTask = Task { @MainActor [weak self] in
            for await _ in KeyboardShortcuts.events(.keyUp, for: .invokeScrollSnap) {
                self?.presentCaptureInterface()
            }
        }
    }

    @MainActor
    private func presentCaptureInterface() {
        guard screenRecordingPermissionWindow == nil,
              whatsNewWindow == nil,
              overlayManager.canPresentOverlay else {
            return
        }

        handleScreenRecordingPermissionOnLaunch()
    }

    @MainActor
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let settingsIndex = appMenu.items.firstIndex(where: {
                  $0.keyEquivalent == ","
                      && $0.keyEquivalentModifierMask.contains(.command)
              }) else {
            return
        }

        appMenu.performActionForItem(at: settingsIndex)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Screen Recording Permission

    @MainActor
    private func handleScreenRecordingPermissionOnLaunch() {
        if presentOverlayIfScreenRecordingIsAllowed() {
            showWhatsNewWindowIfNeeded()
            return
        }

        _ = requestScreenRecordingPermission()

        if !presentOverlayIfScreenRecordingIsAllowed() {
            showScreenRecordingPermissionWindow()
        } else {
            showWhatsNewWindowIfNeeded()
        }
    }

    @MainActor
    @discardableResult
    private func presentOverlayIfScreenRecordingIsAllowed() -> Bool {
        guard hasScreenRecordingPermission() else { return false }

        screenRecordingPermissionWindow?.close()
        screenRecordingPermissionWindow = nil

        return overlayManager.presentOverlay()
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
        if presentOverlayIfScreenRecordingIsAllowed() {
            showWhatsNewWindowIfNeeded()
        } else {
            _ = requestScreenRecordingPermission()
            if presentOverlayIfScreenRecordingIsAllowed() {
                showWhatsNewWindowIfNeeded()
            }
        }
    }

    // MARK: - What's New

    @MainActor
    private func showWhatsNewWindowIfNeeded() {
        guard let version = updateFeedbackManager.pendingVersionToShow else { return }

        let highlights = WhatsNewContent.currentHighlights
        guard !highlights.isEmpty else {
            updateFeedbackManager.markHandled(version: version)
            return
        }

        if let whatsNewWindow {
            whatsNewWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let whatsNewView = WhatsNewView(
            version: version,
            highlights: highlights,
            reportProblem: { [weak self] in
                self?.handleWhatsNewEmailAction(
                    version: version,
                    subject: String(
                        format: LocalizationResolver.string(
                            "whatsNew.problemReportSubject",
                            fallback: "ScrollSnap Problem Report (v%@)"
                        ),
                        version
                    )
                )
            },
            sendFeedback: { [weak self] in
                self?.handleWhatsNewEmailAction(
                    version: version,
                    subject: String(
                        format: LocalizationResolver.string(
                            "whatsNew.feedbackSubject",
                            fallback: "ScrollSnap Feedback (v%@)"
                        ),
                        version
                    )
                )
            },
            dismiss: { [weak self] in
                self?.handleWhatsNewDismiss(version: version)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 576, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationResolver.string(
            "whatsNew.windowTitle",
            fallback: "What's New"
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingView = NSHostingView(rootView: whatsNewView)
        window.contentView = hostingView
        window.setContentSize(NSSize(width: 576, height: hostingView.fittingSize.height))
        window.center()
        overlayManager.suspendFloatingWindows(for: .whatsNew)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        whatsNewWindow = window
        whatsNewWindowVersion = version
    }

    @MainActor
    private func handleWhatsNewDismiss(version: String) {
        updateFeedbackManager.markHandled(version: version)
        whatsNewWindow?.close()
    }

    @MainActor
    private func handleWhatsNewEmailAction(version: String, subject: String) {
        openSupportEmail(subject: subject)
    }

    private func openSupportEmail(subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "yasarberkergungor@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Temporary File Cleanup
    
    /// Cleans up ScrollSnap temporary files older than the specified retention period
    private func cleanupOldTemporaryFiles() {
        // Resolved on the main actor, then swept off it so launch is not blocked on disk I/O.
        let filenamePrefixes = AppText.supportedScreenshotFilenamePrefixes

        Task.detached(priority: .utility) {
            Self.removeTemporaryFiles(withPrefixes: filenamePrefixes, olderThanDays: 7)
        }
    }

    private nonisolated static func removeTemporaryFiles(withPrefixes prefixes: [String], olderThanDays retentionDays: Int) {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory

        do {
            let tempContents = try fileManager.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
                options: .skipsHiddenFiles
            )

            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

            for fileURL in tempContents {
                // Only process files that match ScrollSnap's naming pattern
                guard fileURL.pathExtension == "png",
                      prefixes.contains(where: { fileURL.lastPathComponent.hasPrefix("\($0) ") }) else {
                    continue
                }

                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])

                    // Ensure it's a regular file
                    guard resourceValues.isRegularFile == true else { continue }

                    // Check if file is older than cutoff date
                    if let creationDate = resourceValues.creationDate,
                       creationDate < cutoffDate {
                        try fileManager.removeItem(at: fileURL)
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
