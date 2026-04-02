//
//  SettingsWindowController.swift
//  ScrollSnap
//

import AppKit

class SettingsWindowController: NSWindowController {
    private weak var overlayManager: OverlayManager?
    
    convenience init(overlayManager: OverlayManager) {
        let contentView = SettingsView(overlayManager: overlayManager)
        let contentSize = contentView.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .popUpMenu
        window.title = AppText.preferencesWindowTitle
        window.backgroundColor = NSColor.windowBackgroundColor // Subtle gray background
        self.init(window: window)
        self.overlayManager = overlayManager
        window.contentView = contentView
        window.setContentSize(contentSize)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

class SettingsView: NSView {
    private weak var overlayManager: OverlayManager?
    private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    
    init(overlayManager: OverlayManager) {
        self.overlayManager = overlayManager
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let languageLabel = NSTextField(labelWithString: AppText.language)
        languageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        languageLabel.setContentHuggingPriority(.required, for: .horizontal)

        configureLanguagePopUpButton()

        let languageRow = NSStackView(views: [languageLabel, languagePopUpButton])
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 12
        languageRow.translatesAutoresizingMaskIntoConstraints = false

        let relaunchLabel = NSTextField(wrappingLabelWithString: AppText.relaunchToApplyLanguageChanges)
        relaunchLabel.font = .systemFont(ofSize: 11)
        relaunchLabel.textColor = .secondaryLabelColor
        relaunchLabel.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(
            title: AppText.resetSelectionAndMenuPositions,
            target: self,
            action: #selector(resetPositions)
        )
        resetButton.bezelStyle = .push
        resetButton.font = .systemFont(ofSize: 13)
        resetButton.wantsLayer = true
        resetButton.layer?.cornerRadius = 6
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        
        let versionLabel = NSTextField(labelWithString: "")
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            versionLabel.stringValue = AppText.versionLabel(for: version)
        }
        
        let stackView = NSStackView(views: [languageRow, relaunchLabel, resetButton, versionLabel])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            languagePopUpButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
    }

    private func configureLanguagePopUpButton() {
        languagePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        languagePopUpButton.removeAllItems()
        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(languageSelectionChanged(_:))

        for language in AppLanguage.allCases {
            languagePopUpButton.addItem(withTitle: language.localizedTitle)
            languagePopUpButton.lastItem?.representedObject = language.rawValue
        }

        selectCurrentLanguage()
    }

    private func selectCurrentLanguage() {
        let selectedLanguage = AppLanguage.current()
        for item in languagePopUpButton.itemArray where item.representedObject as? String == selectedLanguage.rawValue {
            languagePopUpButton.select(item)
            return
        }
    }
    
    @objc private func resetPositions() {
        overlayManager?.resetPositions()
    }

    @objc private func languageSelectionChanged(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            selectCurrentLanguage()
            return
        }

        language.persist()
    }
}
