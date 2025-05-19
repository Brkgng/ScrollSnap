//
//  SettingsWindowController.swift
//  ScrollSnap
//

import AppKit

class SettingsWindowController: NSWindowController {
    private weak var overlayManager: OverlayManager?
    
    convenience init(overlayManager: OverlayManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .popUpMenu
        window.title = "ScrollSnap Preferences"
        window.backgroundColor = NSColor.windowBackgroundColor // Subtle gray background
        self.init(window: window)
        self.overlayManager = overlayManager
        window.contentView = SettingsView(frame: window.contentRect(forFrameRect: window.frame), overlayManager: overlayManager)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class SettingsView: NSView {
    private weak var overlayManager: OverlayManager?
    
    init(frame: NSRect, overlayManager: OverlayManager) {
        self.overlayManager = overlayManager
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        let resetButton = NSButton(
            title: "Reset Selection and Menu Positions",
            target: self,
            action: #selector(resetPositions)
        )
        resetButton.frame = NSRect(x: 10, y: 20, width: 280, height: 20) // Centered in smaller window
        resetButton.bezelStyle = .push // Modern macOS button style
        resetButton.font = .systemFont(ofSize: 13)
        resetButton.wantsLayer = true
        resetButton.layer?.cornerRadius = 6 // Soften edges
        
        addSubview(resetButton)
    }
    
    @objc private func resetPositions() {
        overlayManager?.resetPositions()
    }
}
