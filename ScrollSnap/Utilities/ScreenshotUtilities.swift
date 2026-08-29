//
//  ScreenshotUtilities.swift
//  ScrollSnap
//

import ScreenCaptureKit

// MARK: - Public API

@MainActor
final class ScreenshotCaptureSession {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration
    private let imageSize: NSSize

    init?(rectangle: NSRect) async {
        guard let activeScreen = screenContainingPoint(rectangle.origin),
              let captureContext = await resolveCaptureContext(for: activeScreen) else {
            print("Error: Unable to determine active screen or display.")
            return nil
        }

        let adjustedRect = adjustRectForScreen(rectangle, for: activeScreen)
        let filter = SCContentFilter(
            display: captureContext.display,
            excludingApplications: captureContext.excludedApplications,
            exceptingWindows: []
        )
        let scaleFactor = CGFloat(filter.pointPixelScale)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = adjustedRect
        configuration.width = Int((adjustedRect.width * scaleFactor).rounded())
        configuration.height = Int((adjustedRect.height * scaleFactor).rounded())
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false

        self.filter = filter
        self.configuration = configuration
        imageSize = adjustedRect.size
    }

    func capture() async -> NSImage? {
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSImage(cgImage: image, size: imageSize)
        } catch {
            print("Error capturing screenshot: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Captures a single screenshot of the specified rectangle on the active screen.
@MainActor
func captureSingleScreenshot(_ rectangle: NSRect) async -> NSImage? {
    guard let session = await ScreenshotCaptureSession(rectangle: rectangle) else { return nil }
    return await session.capture()
}

/// Saves the captured image to a specified destination or the default location.
///
/// Supports saving to a file, copying to the clipboard, or opening in Preview. The destination is determined by the provided parameter, falling back to UserDefaults or the default downloads destination.
///
/// - Parameters:
///   - image: The `NSImage` to save.
///   - destination: An optional save destination. If `nil`, uses the saved user preference or the default destination.
/// - Returns: A `URL` to the saved file if saved to the file system, or `nil` if saved to Clipboard/Preview or if saving fails.
/// - Note: Generates a filename with a timestamp (e.g., "Screenshot 2025-03-11 at 14.30.00.png").
@discardableResult
func saveImage(_ image: NSImage, to destination: SaveDestination? = nil) -> URL? {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG data.")
        return nil
    }
    
    let filename = getFileName()
    let selectedDestination = destination ?? SaveDestination.current()

    switch selectedDestination.behavior {
    case .clipboard:
        saveToClipboard(pngData)
        return nil
    case .preview:
        openInPreview(pngData, filename)
        return nil
    case .file:
        guard let folderURL = getFolderURL(for: selectedDestination) else {
            print("Failed to get \(selectedDestination.rawValue) URL.")
            return nil
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let fileURL = folderURL.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save image: \(error.localizedDescription)")
            return nil
        }
    }
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

private struct ScreenCaptureContext {
    let display: SCDisplay
    let excludedApplications: [SCRunningApplication]
}

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

/// Resolves the ScreenCaptureKit display and the current app exclusion list from one content snapshot.
///
/// The filtered retrieval matches Apple's sample usage and avoids re-enumerating shareable content for
/// the same screenshot.
private func resolveCaptureContext(for nsScreen: NSScreen) async -> ScreenCaptureContext? {
    guard let screenID = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
        print("Error: Unable to retrieve screen ID.")
        return nil
    }
    
    do {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        guard let display = shareableContent.displays.first(where: { $0.displayID == screenID }) else {
            print("Error: Unable to resolve ScreenCaptureKit display.")
            return nil
        }
        
        let currentPID = NSRunningApplication.current.processIdentifier

        let excludedApplications = shareableContent.applications.filter { $0.processID == currentPID }
        if excludedApplications.isEmpty {
            print("Current application not found in SCShareableContent.")
        }
        
        return ScreenCaptureContext(display: display, excludedApplications: excludedApplications)
    } catch {
        print("Error fetching shareable content: \(error)")
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
    } catch {
        print("Failed to write temporary file for Preview: \(error.localizedDescription)")
    }
}

/// Gets the URL for a folder, prompting for access if necessary.
/// - Parameter destination: The file-system backed destination.
/// - Returns: The folder URL, or nil if permission is denied or unavailable.
private func getFolderURL(for destination: SaveDestination) -> URL? {
    guard let bookmarkKey = destination.bookmarkKey else {
        return nil
    }

    if let cachedURL = getCachedFolderURL(for: destination, bookmarkKey: bookmarkKey) {
        return cachedURL
    }

    guard let chosenURL = promptForFolderAccess(for: destination, bookmarkKey: bookmarkKey) else {
        print("User cancelled \(destination.rawValue) access.")
        return nil
    }

    return chosenURL
}

private func getFileName() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = Constants.dateFormat
    let timestamp = dateFormatter.string(from: Date())
    let filename = "\(AppText.screenshotFilenamePrefix) \(timestamp).png"
    return filename
}

// MARK: - Permission Helpers

/// Prompts the user to select a folder and caches the result as a security-scoped bookmark.
/// - Parameters:
///   - destination: The destination that requires file-system access.
///   - bookmarkKey: The UserDefaults key to store the bookmark.
/// - Returns: The selected folder URL, or nil if cancelled.
private func promptForFolderAccess(for destination: SaveDestination, bookmarkKey: String) -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.canCreateDirectories = false
    openPanel.message = destination.folderAccessMessage ?? ""
    openPanel.directoryURL = defaultDirectoryURL(for: destination)
    
    let response = openPanel.runModal()
    guard response == .OK, let selectedURL = openPanel.url else {
        return nil
    }
    
    // Cache as a security-scoped bookmark
    do {
        let bookmarkData = try selectedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        print("\(destination.rawValue) permission cached.")
        // Balance the caller's `stopAccessingSecurityScopedResource()`, which runs for both the
        // freshly picked and the restored-from-bookmark folder.
        _ = selectedURL.startAccessingSecurityScopedResource()
        return selectedURL
    } catch {
        print("Failed to create bookmark for \(destination.rawValue): \(error)")
        return nil
    }
}

/// Retrieves the cached folder URL from UserDefaults, starting access if necessary.
/// - Parameters:
///   - destination: The destination that requires file-system access.
///   - bookmarkKey: The UserDefaults key where the bookmark is stored.
/// - Returns: The folder URL if available, or nil if not cached or inaccessible.
private func getCachedFolderURL(for destination: SaveDestination, bookmarkKey: String) -> URL? {
    guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
        return nil
    }
    
    do {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing \(destination.rawValue) URL.")
            return nil
        }
        
        // If stale, refresh the bookmark
        if isStale {
            let newBookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(newBookmarkData, forKey: bookmarkKey)
            print("Refreshed stale \(destination.rawValue) bookmark.")
        }
        
        return url
    } catch {
        print("Failed to resolve \(destination.rawValue) bookmark: \(error)")
        return nil
    }
}

private func defaultDirectoryURL(for destination: SaveDestination) -> URL? {
    guard let directory = destination.searchPathDirectory else {
        return nil
    }

    return FileManager.default.urls(for: directory, in: .userDomainMask).first
}

/// Returns whether screen recording permission is currently granted.
@MainActor
func hasScreenRecordingPermission() -> Bool {
    CGPreflightScreenCaptureAccess()
}

/// Requests screen recording permission if it is not already granted.
/// - Returns: `true` if the request API reports access was granted, `false` otherwise.
@MainActor
func requestScreenRecordingPermission() -> Bool {
    CGRequestScreenCaptureAccess()
}
