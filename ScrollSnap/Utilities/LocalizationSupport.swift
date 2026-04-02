//
//  LocalizationSupport.swift
//  ScrollSnap
//

import AppKit

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case turkish = "tr"

    static let storageKey = "SelectedAppLanguage"
    static let defaultValue: AppLanguage = .system

    func persist(userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.storageKey)
    }

    static func current(userDefaults: UserDefaults = .standard) -> AppLanguage {
        guard let storedValue = userDefaults.string(forKey: storageKey),
              let language = AppLanguage(rawValue: storedValue) else {
            return defaultValue
        }

        return language
    }

    var localizedTitle: String {
        switch self {
        case .system:
            return LocalizationResolver.string("System Default", fallback: "System Default")
        case .english:
            return LocalizationResolver.string("English", fallback: "English")
        case .turkish:
            return LocalizationResolver.string("Turkish", fallback: "Turkish")
        }
    }
}

enum LocalizationResolver {
    private static let tableName = "Localizable"
    static let launchLanguage = AppLanguage.current()
    private static let launchBundle = bundle(for: launchLanguage)

    static func string(_ key: String, fallback: String, language: AppLanguage? = nil) -> String {
        let bundle = language.map(bundle(for:)) ?? launchBundle
        let localizedString = bundle.localizedString(forKey: key, value: fallback, table: tableName)
        return localizedString.isEmpty ? fallback : localizedString
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let localization = resolvedLocalization(for: language),
              let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main
        }

        return bundle
    }

    private static func resolvedLocalization(for language: AppLanguage) -> String? {
        let availableLocalizations = Bundle.main.localizations.filter { $0 != "Base" }

        let preferredLocalizations: [String]
        switch language {
        case .system:
            preferredLocalizations = Bundle.preferredLocalizations(from: availableLocalizations)
        case .english, .turkish:
            preferredLocalizations = Bundle.preferredLocalizations(
                from: availableLocalizations,
                forPreferences: [language.rawValue]
            )
        }

        if let localization = preferredLocalizations.first {
            return localization
        }

        if let developmentLocalization = Bundle.main.developmentLocalization,
           availableLocalizations.contains(developmentLocalization) {
            return developmentLocalization
        }

        return availableLocalizations.first
    }
}

enum AppText {
    static var aboutApp: String {
        text("About ScrollSnap")
    }

    static var settings: String {
        text("Settings…")
    }

    static var quitApp: String {
        text("Quit ScrollSnap")
    }

    static var capture: String {
        text("Capture")
    }

    static var save: String {
        text("Save")
    }

    static var options: String {
        text("Options")
    }

    static var saveTo: String {
        text("Save to")
    }

    static var settingsWindowTitle: String {
        text("ScrollSnap Settings")
    }

    static var resetSelectionAndMenuPositions: String {
        text("Reset Selection and Menu Positions")
    }

    static var version: String {
        text("Version")
    }

    static var language: String {
        text("Language")
    }

    static var relaunchToApplyLanguageChanges: String {
        text("Relaunch ScrollSnap to apply language changes.")
    }

    static var moveAccessibility: String {
        text("Move")
    }

    static var cancelAccessibility: String {
        text("Cancel")
    }

    static var delete: String {
        text("Delete")
    }

    static var close: String {
        text("Close")
    }

    static var screenshotFilenamePrefix: String {
        text("Screenshot")
    }

    static var supportedScreenshotFilenamePrefixes: [String] {
        AppLanguage.allCases
            .filter { $0 != .system }
            .map { LocalizationResolver.string("Screenshot", fallback: "Screenshot", language: $0) }
    }

    static func versionLabel(for version: String) -> String {
        "\(self.version) \(version)"
    }

    private static func text(_ key: String) -> String {
        LocalizationResolver.string(key, fallback: key)
    }
}

enum SaveBehavior {
    case file
    case clipboard
    case preview
}

enum SaveDestination: String, CaseIterable {
    case desktop
    case documents
    case downloads
    case clipboard
    case preview

    static let storageKey = Constants.Menu.Options.selectedDestinationKey
    static let defaultValue: SaveDestination = .downloads

    var behavior: SaveBehavior {
        switch self {
        case .desktop, .documents, .downloads:
            return .file
        case .clipboard:
            return .clipboard
        case .preview:
            return .preview
        }
    }

    var localizedTitle: String {
        switch self {
        case .desktop:
            return LocalizationResolver.string("Desktop", fallback: "Desktop")
        case .documents:
            return LocalizationResolver.string("Documents", fallback: "Documents")
        case .downloads:
            return LocalizationResolver.string("Downloads", fallback: "Downloads")
        case .clipboard:
            return LocalizationResolver.string("Clipboard", fallback: "Clipboard")
        case .preview:
            return LocalizationResolver.string("Preview", fallback: "Preview")
        }
    }

    var bookmarkKey: String? {
        switch self {
        case .desktop:
            return "desktopBookmark"
        case .documents:
            return "documentsBookmark"
        case .downloads:
            return "downloadsBookmark"
        case .clipboard, .preview:
            return nil
        }
    }

    var searchPathDirectory: FileManager.SearchPathDirectory? {
        switch self {
        case .desktop:
            return .desktopDirectory
        case .documents:
            return .documentDirectory
        case .downloads:
            return .downloadsDirectory
        case .clipboard, .preview:
            return nil
        }
    }

    var folderAccessMessage: String? {
        switch self {
        case .desktop:
            return LocalizationResolver.string(
                "Please select your Desktop folder to grant ScrollSnap permission to save screenshots there.",
                fallback: "Please select your Desktop folder to grant ScrollSnap permission to save screenshots there."
            )
        case .documents:
            return LocalizationResolver.string(
                "Please select your Documents folder to grant ScrollSnap permission to save screenshots there.",
                fallback: "Please select your Documents folder to grant ScrollSnap permission to save screenshots there."
            )
        case .downloads:
            return LocalizationResolver.string(
                "Please select your Downloads folder to grant ScrollSnap permission to save screenshots there.",
                fallback: "Please select your Downloads folder to grant ScrollSnap permission to save screenshots there."
            )
        case .clipboard, .preview:
            return nil
        }
    }

    func persist(userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.storageKey)
    }

    static func current(userDefaults: UserDefaults = .standard) -> SaveDestination {
        guard let storedValue = userDefaults.string(forKey: storageKey) else {
            return defaultValue
        }

        return fromStoredValue(storedValue)
    }

    static func fromStoredValue(_ storedValue: String) -> SaveDestination {
        if let destination = SaveDestination(rawValue: storedValue) {
            return destination
        }

        switch storedValue {
        case "Desktop":
            return .desktop
        case "Documents":
            return .documents
        case "Downloads":
            return .downloads
        case "Clipboard":
            return .clipboard
        case "Preview":
            return .preview
        default:
            return defaultValue
        }
    }
}

enum MenuBarLayout {
    static let height: CGFloat = Constants.Menu.height
    static let dragWidth: CGFloat = 35.0
    static let cancelWidth: CGFloat = 40.0

    private static let symbolBounds = CGRect(x: 0, y: 0, width: 12, height: 8)
    private static let horizontalPadding: CGFloat = 18.0

    static var optionsWidth: CGFloat {
        buttonWidth(for: AppText.options, symbol: "chevron.down")
    }

    static var captureWidth: CGFloat {
        max(
            buttonWidth(for: AppText.capture, symbol: "return"),
            buttonWidth(for: AppText.save, symbol: "return")
        )
    }

    static var totalWidth: CGFloat {
        dragWidth + cancelWidth + optionsWidth + captureWidth
    }

    static func attributedLabel(_ text: String, symbol: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Constants.Menu.Button.textColor,
            .font: Constants.Menu.Button.textFont,
        ]

        let label = NSMutableAttributedString(string: "\(text) ", attributes: attributes)
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageAttachment.bounds = symbolBounds
        label.append(NSAttributedString(attachment: imageAttachment))

        return label
    }

    private static func buttonWidth(for text: String, symbol: String) -> CGFloat {
        ceil(attributedLabel(text, symbol: symbol).size().width + (horizontalPadding * 2))
    }
}
