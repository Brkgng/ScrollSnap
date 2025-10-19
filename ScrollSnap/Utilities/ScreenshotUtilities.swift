//
//  ScreenshotUtilities.swift
//  ScrollSnap
//

import ScreenCaptureKit

// MARK: - Public API

/// Captures a single screenshot of the specified rectangle on the active screen.
///
/// This function configures ScreenCaptureKit to capture a region excluding the current app (e.g., the overlay UI) and returns the result as an `NSImage`. It’s used for both single captures and as a building block for scrolling captures.
///
/// - Parameter rectangle: The `NSRect` defining the capture area in screen coordinates.
/// - Returns: An `NSImage` of the captured area, or `nil` if capture fails (e.g., due to invalid screen, app, or display).
/// - Note: Adjusts the rectangle for the screen’s coordinate system and scales the output based on the display’s pixel scale.
func captureSingleScreenshot(_ rectangle: NSRect) async -> NSImage? {
    guard let activeScreen = screenContainingPoint(rectangle.origin),
          let currentApp = await findCurrentSCApplication(),
          let display = await getSCDisplay(from: activeScreen) else {
        print("Error: Unable to determine active screen or display.")
        return nil
    }
    
    let adjustedRect = adjustRectForScreen(rectangle, for: activeScreen)
    let filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
    let scaleFactor = Int(filter.pointPixelScale)
    
    let width = Int(adjustedRect.width) * scaleFactor
    let height = Int(adjustedRect.height) * scaleFactor
    
    let config = SCStreamConfiguration()
    config.sourceRect = adjustedRect
    config.width = width
    config.height = height
    config.colorSpaceName = CGColorSpace.sRGB
    config.showsCursor = false
    
    do {
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let nsImage = NSImage(cgImage: image, size: adjustedRect.size)
        return nsImage
    } catch {
        print("Error capturing screenshot: \(error.localizedDescription)")
        return nil
    }
}

/// Saves the captured image to a specified destination or the default location.
///
/// Supports saving to a file (Desktop, Documents, Downloads), copying to the clipboard, or opening in Preview. The destination is determined by the provided parameter, falling back to UserDefaults or a default ("Downloads").
///
/// - Parameters:
///   - image: The `NSImage` to save.
///   - destination: An optional `String` specifying the save destination (e.g., "Desktop", "Clipboard"). If `nil`, uses UserDefaults or "Downloads".
/// - Returns: A `URL` to the saved file if saved to the file system, or `nil` if saved to Clipboard/Preview or if saving fails.
/// - Note: Generates a filename with a timestamp (e.g., "Screenshot 2025-03-11 at 14.30.00.png").
@discardableResult
func saveImage(_ image: NSImage, to destination: String? = nil) -> URL? {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG data.")
        return nil
    }
    
    let filename = getFileName()
    let selectedDestination = destination ?? UserDefaults.standard.string(forKey: Constants.Menu.Options.selectedDestinationKey) ?? Constants.Menu.Options.defaultDestination
    
    var fileURL: URL
    
    switch selectedDestination {
    case "Desktop":
        guard let desktopURL = getFolderURL(for: "Desktop", bookmarkKey: "desktopBookmark") else {
            print("Failed to get Desktop URL.")
            return nil
        }
        fileURL = desktopURL.appendingPathComponent(filename)
    case "Documents":
        guard let documentsURL = getFolderURL(for: "Documents", bookmarkKey: "documentsBookmark") else {
            print("Failed to get Documents URL.")
            return nil
        }
        fileURL = documentsURL.appendingPathComponent(filename)
    case "Downloads":
        guard let downloadsURL = getFolderURL(for: "Downloads", bookmarkKey: "downloadsBookmark") else {
            print("Failed to get Downloads URL.")
            return nil
        }
        fileURL = downloadsURL.appendingPathComponent(filename)
    case "Clipboard":
        // Save to clipboard instead of file
        saveToClipboard(pngData)
        return nil
    case "Preview":
        //Open in Preview app
        openInPreview(pngData, filename)
        return nil
    default:
        // Use default destionation if the selected destination is not recognized
        let defaultDestination = Constants.Menu.Options.defaultDestination
        fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("\(defaultDestination)/\(filename)")
    }
    
    do {
        try pngData.write(to: fileURL)
        return fileURL
    } catch {
        print("Failed to save image: \(error.localizedDescription)")
    }
    
    return nil
}

/// Saves an image to a temporary file for use in drag-and-drop or Preview.
///
/// - Parameter image: The `NSImage` to save.
/// - Returns: A `URL` to the temporary file, or `nil` if saving fails.
/// - Note: Uses a UUID-based filename (e.g., "123e4567-e89b-12d3-a456-426614174000.png") in the system’s temp directory.
func saveImageToTemporaryFile(_ image: NSImage) -> URL? {
    guard let pngData = image.pngData else { return nil }
    let filename = getFileName()
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
        try pngData.write(to: tempURL)
        return tempURL
    } catch {
        print("Failed to write temporary file: \(error)")
        return nil
    }
    
}

// MARK: - Capture Helpers

/// Determines which screen contains a given point.
///
/// - Parameter point: The `NSPoint` to check against all available screens.
/// - Returns: The `NSScreen` whose frame contains the point, or `nil` if no screen contains it.
/// - Note: Uses the first matching screen; assumes screens don’t overlap significantly.
private func screenContainingPoint(_ point: NSPoint) -> NSScreen? {
    return NSScreen.screens.first { $0.frame.contains(point) }
}

/// Adjusts a rectangle’s Y-coordinate to match the screen’s coordinate system.
///
/// macOS uses a bottom-left origin, while ScreenCaptureKit expects a top-left origin. This function flips the Y-axis accordingly.
///
/// - Parameters:
///   - rect: The `NSRect` to adjust.
///   - screen: The `NSScreen` providing the coordinate context.
/// - Returns: A new `NSRect` with adjusted coordinates.
/// - Note: Subtracts screen’s minX/minY to align with the screen’s local origin.
private func adjustRectForScreen(_ rect: NSRect, for screen: NSScreen) -> NSRect {
    let screenHeight = screen.frame.height + screen.frame.minY
    return NSRect(
        x: rect.origin.x - screen.frame.minX,
        y: screenHeight - rect.origin.y - rect.height,
        width: rect.width,
        height: rect.height
    )
}

/// Retrieves the corresponding `SCDisplay` for a given `NSScreen` using its display ID.
///
/// This function is used to bridge AppKit's `NSScreen` with ScreenCaptureKit's `SCDisplay`, which is required for screenshot capture operations.
///
/// - Parameter nsScreen: The `NSScreen` to find the corresponding `SCDisplay` for.
/// - Returns: The matching `SCDisplay` if found, or `nil` if the screen ID cannot be retrieved or no matching display exists.
private func getSCDisplay(from nsScreen: NSScreen) async -> SCDisplay? {
    guard let screenID = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        print("Error: Unable to retrieve screen ID.")
        return nil
    }
    
    do {
        let displays = try await SCShareableContent.current.displays
        return displays.first { $0.displayID == screenID }
    } catch {
        print("Error fetching SCDisplay: \(error)")
        return nil
    }
}

/// Finds the currently running application in ScreenCaptureKit's shareable content.
///
/// This is used to exclude the ScrollSnap app itself from screenshot captures, ensuring the overlay UI doesn't appear in the output.
///
/// - Returns: The `SCRunningApplication` representing the current app if found, or `nil` if not found or an error occurs.
private func findCurrentSCApplication() async -> SCRunningApplication? {
    do {
        let apps = try await SCShareableContent.current.applications
        let currentPID = NSRunningApplication.current.processIdentifier
        
        // Search for the application based on its process ID.
        if let app = apps.first(where: { $0.processID == currentPID }) {
            return app
        } else {
            print("Current application not found in SCShareableContent.")
            return nil
        }
    } catch {
        print("Error fetching applications: \(error)")
        return nil
    }
}

// MARK: - Destination Helpers

/// Saves PNG data to the system clipboard.
///
/// - Parameter pngData: The `Data` in PNG format to copy.
/// - Note: Clears the clipboard before writing; does not verify success.
private func saveToClipboard(_ pngData: Data) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(pngData, forType: .png)
    NSApplication.shared.terminate(nil)
}

/// Opens a PNG image in the Preview app by saving it to a temporary file.
///
/// - Parameters:
///   - pngData: The `Data` in PNG format to open.
///   - filename: The base filename (default "Screenshot") for the temp file
private func openInPreview(_ pngData: Data, _ filename: String = "Screenshot.png") {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
        try pngData.write(to: tempURL)
        NSWorkspace.shared.open(tempURL)
        NSApplication.shared.terminate(nil)
    } catch {
        print("Failed to write temporary file for Preview: \(error.localizedDescription)")
    }
}

/// Gets the URL for a folder, prompting for access if necessary.
/// - Parameters:
///   - folderName: The name of the folder (e.g., "Desktop", "Documents").
///   - bookmarkKey: The UserDefaults key for the bookmark.
/// - Returns: The folder URL, or nil if permission is denied or unavailable.
private func getFolderURL(for folderName: String, bookmarkKey: String) -> URL? {
    if let cachedURL = getCachedFolderURL(folderName: folderName, bookmarkKey: bookmarkKey) {
        return cachedURL
    } else {
        // Prompt user and cache the result
        guard let chosenURL = promptForFolderAccess(folderName: folderName, bookmarkKey: bookmarkKey) else {
            print("User cancelled \(folderName) access.")
            return nil
        }
        return chosenURL
    }
}

private func getFileName() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = Constants.dateFormat
    let timestamp = dateFormatter.string(from: Date())
    let filename = "Screenshot \(timestamp).png"
    return filename
}

// MARK: - Permission Helpers

/// Prompts the user to select a folder and caches the result as a security-scoped bookmark.
/// - Parameters:
///   - folderName: The name of the folder (e.g., "Desktop", "Documents").
///   - bookmarkKey: The UserDefaults key to store the bookmark.
/// - Returns: The selected folder URL, or nil if cancelled.
private func promptForFolderAccess(folderName: String, bookmarkKey: String) -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.canCreateDirectories = false
    openPanel.message = "Please select your \(folderName) folder to grant ScrollSnap permission to save screenshots there."
    openPanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderName)
    
    let response = openPanel.runModal()
    guard response == .OK, let selectedURL = openPanel.url else {
        return nil
    }
    
    // Cache as a security-scoped bookmark
    do {
        let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        print("\(folderName) permission cached.")
        return selectedURL
    } catch {
        print("Failed to create bookmark for \(folderName): \(error)")
        return nil
    }
}

/// Retrieves the cached folder URL from UserDefaults, starting access if necessary.
/// - Parameters:
///   - folderName: The name of the folder (e.g., "Desktop", "Documents").
///   - bookmarkKey: The UserDefaults key where the bookmark is stored.
/// - Returns: The folder URL if available, or nil if not cached or inaccessible.
private func getCachedFolderURL(folderName: String, bookmarkKey: String) -> URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
        return nil
    }
    
    do {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing \(folderName) URL.")
            return nil
        }
        
        // If stale, refresh the bookmark
        if isStale {
            let newBookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(newBookmarkData, forKey: bookmarkKey)
            print("Refreshed stale \(folderName) bookmark.")
        }
        
        return url
    } catch {
        print("Failed to resolve \(folderName) bookmark: \(error)")
        return nil
    }
}

/// Checks if screen recording permission is granted, and requests it if not.
/// - Returns: `true` if permission is granted, `false` otherwise.
func checkScreenRecordingPermission() async -> Bool {
    let isAuthorized = await withCheckedContinuation { continuation in
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            continuation.resume(returning: CGPreflightScreenCaptureAccess())
        }
    }
    
    if !isAuthorized {
        print("Screen recording permission not granted. Prompting user...")
        CGRequestScreenCaptureAccess()
        return false
    }
    
    return true
}
