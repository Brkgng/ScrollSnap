//
//  StatusItemController.swift
//  ScrollSnap
//

import AppKit

/// Whether ScrollSnap shows its menu bar icon.
enum MenuBarIconSettings {
    static func isVisible(userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: Constants.MenuBarIcon.visibleKey) as? Bool ?? true
    }
}

extension UserDefaults {
    /// Key-value observing shim for `Constants.MenuBarIcon.visibleKey`. The property name has to
    /// match the defaults key exactly for `observe(\.ShowMenuBarIcon)` to receive changes.
    @objc dynamic var ShowMenuBarIcon: Bool {
        bool(forKey: Constants.MenuBarIcon.visibleKey)
    }
}

/// Owns the menu bar icon, which is the app's only persistent interface: ScrollSnap runs as an
/// agent (`LSUIElement`), so without it there is no way to capture, open settings, or quit unless
/// the overlay happens to be on screen.
@MainActor
final class StatusItemController: NSObject {
    var capture: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}

    private var statusItem: NSStatusItem?

    var isVisible: Bool {
        statusItem != nil
    }

    /// Adds or removes the icon to match the stored preference.
    func syncWithPreference() {
        if MenuBarIconSettings.isVisible() {
            show()
        } else {
            hide()
        }
    }

    func show() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let appName = Self.appName

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: appName)
            icon?.isTemplate = true // Follows the menu bar's light and dark appearance.
            button.image = icon
            button.toolTip = appName
        }

        statusItem.menu = makeMenu()
        self.statusItem = statusItem
    }

    func hide() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem(title: AppText.capture, action: #selector(handleCapture)))
        menu.addItem(.separator())
        // No key equivalent for capture: the recorder in Settings refuses shortcuts already taken by
        // a menu item, and that would make the current global shortcut unselectable.
        menu.addItem(makeItem(title: AppText.settings, action: #selector(handleOpenSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: AppText.quitApp, action: #selector(handleQuit), keyEquivalent: "q"))
        return menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func handleCapture() {
        capture()
    }

    @objc private func handleOpenSettings() {
        openSettings()
    }

    @objc private func handleQuit() {
        quit()
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ScrollSnap"
    }
}
