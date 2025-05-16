# ScrollSnap

ScrollSnap is an open-source macOS application designed to capture scrolling screenshots with a customizable selection area and menu interface. It allows users to define a capture region, take stitched scrolling screenshots, and save them to various destinations (e.g., Desktop, Clipboard, Preview). Built with Swift and leveraging AppKit and ScreenCaptureKit, ScrollSnap provides a sleek overlay-based UI for precise control.

<div style="text-align: center;">
  <img src="assets/preview.gif" alt="ScrollSnap Demo" style="width: 700px; height: 400px;">
</div>

## Download

- 📦 [Download ZIP from GitHub Releases](https://github.com/brkgng/ScrollSnap/releases/latest) - **Free**
- 🍎 [Download on the App Store](https://apps.apple.com/app/scrollsnap/id6744903723) – Paid version for users who prefer App Store convenience

## Features

- **Customizable Selection Area**: Resize and drag a selection rectangle to define the capture region.
- **Scrolling Capture**: Automatically stitches multiple screenshots into a single image for capturing long content.
- **Interactive Menu**: Includes options to capture, save, reset positions, or cancel, with a draggable interface.
- **Thumbnail Preview**: Displays a draggable thumbnail of the captured image with swipe-to-save or right-click options.
- **Save Destinations**: Supports saving to Desktop, Documents, Downloads, Clipboard, or opening in Preview.
- **Preferences**: Reset selection and menu positions via a settings window (Command + ,).

## Requirements

- macOS 12.0 or later (requires ScreenCaptureKit framework).
- Xcode 14.0 or later for development.

## Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/brkgng/ScrollSnap.git
   cd ScrollSnap
   ```
2. **Open in Xcode**:

- Open `ScrollSnap.xcodeproj`

3. **Build and Run**:

- Press `Cmd + R` to build and run.
- **Note**: Ensure the app has screen recording permissions enabled in System Settings > Security & Privacy.

## Usage

1. **Launch the App**:

- ScrollSnap starts automatically, displaying an overlay with a selection rectangle and menu bar.

2. **Adjust the Selection**:

- Drag the rectangle to move it or use the resize handles to adjust its size.

3. **Capture a Screenshot**:

- For scrolling capture, click "Capture" to start, then "Save" to stop and stitch the images.

4. **Interact with the Thumbnail**:

- Drag the thumbnail to copy the image elsewhere, swipe right to save, or right-click for options (Show in Finder, Delete, Close).

5. **Save Options**:

- Use the "Options" menu to set the save destination (Desktop, Clipboard, etc.).

6. **Preferences**:

- Press `Cmd + ,` to open the settings window and reset positions if needed.

7. **Quit**:

- Press `Esc` or select "Quit ScrollSnap" from the main menu.

## Project Structure

```
ScrollSnap
│── App
│   │── ScrollSnapApp.swift         # App entry point (SwiftUI)
│   │── AppDelegate.swift          # Menu and settings setup
│── Controllers
│   │── SettingsWindowController.swift  # Preferences window
│── Utilities
│   │── Constants.swift            # App-wide constants
│   │── ScreenshotUtilities.swift  # Screenshot capture and save logic
│── Views
│   │── OverlayView.swift          # Main overlay coordinator
│   │── ContentView.swift          # SwiftUI entry point
│   │── SelectionRectangleView.swift  # Selection area UI
│   │── MenuBarView.swift          # Menu bar UI
│   │── ThumbnailView.swift        # Thumbnail preview UI
│── Managers
│   │── OverlayManager.swift       # Overlay and state management
│   │── StitchingManager.swift     # Image stitching for scrolling capture
```

## How It Works

- **Overlay System**: `OverlayManager` creates overlays on all screens, managed by `OverlayView`, which delegates drawing and interaction to `SelectionRectangleView` and `MenuBarView`.
- **Screenshot Capture**: `ScreenshotUtilities` uses ScreenCaptureKit to capture the defined rectangle, excluding the app’s UI.
- **Scrolling Capture**: `StitchingManager` combines screenshots into a single image using overlap detection.
- **Thumbnail**: `ThumbnailView` provides an interactive preview with drag-and-drop and swipe gestures.

## Contributing

ScrollSnap is an open-source project, and we welcome contributions! If you’d like to improve it:

- **Report Issues**: Open an issue on the [GitHub repository](https://github.com/brkgng/ScrollSnap/issues) for bugs or feature requests.
- **Submit Pull Requests**:
  1. Fork the repo.
  2. Create a new branch for your changes (e.g., `git checkout -b feature/your-feature-name`).
  3. Make your changes and commit them.
  4. Submit a pull request with your improvements.

## License

MIT Licensed.
