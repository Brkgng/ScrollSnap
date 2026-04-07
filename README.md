# ScrollSnap

![macOS](https://img.shields.io/badge/macOS-black?style=flat-square)
[![License: MIT](https://img.shields.io/badge/License-MIT-black?style=flat-square)](#license)
[![App Store](https://img.shields.io/badge/App%20Store-Download-black?style=flat-square&logo=appstore)](https://apps.apple.com/app/scrollsnap/id6744903723)

ScrollSnap is an open-source macOS application designed to capture scrolling screenshots with a customizable selection area and menu interface. It allows users to define a capture region, take stitched scrolling screenshots, and save them to various destinations (e.g., Desktop, Clipboard, Preview). Built with Swift and leveraging AppKit and ScreenCaptureKit, ScrollSnap provides a sleek overlay-based UI for precise control.

<div style="text-align: center;">
  <img src="assets/preview.gif" alt="ScrollSnap Demo" style="width: 700px; height: 400px;">
</div>

## Download

- 🍎 [Download on the App Store](https://apps.apple.com/app/scrollsnap/id6744903723) – _Supports App Store-managed installation and updates._
- 📦 [Download ZIP from GitHub Releases](https://github.com/brkgng/ScrollSnap/releases/latest) - _The free, compiled binary. Requires manual downloads to install future updates._

## Features

- **Customizable Selection Area**: Resize and drag a selection rectangle to define the capture region.
- **Scrolling Capture**: Automatically stitches multiple screenshots into a single image for capturing long content.
- **Keyboard Shortcut**: Press `Return` while the overlay is active to start or stop scrolling capture.
- **Interactive Menu**: Includes options to capture, save, reset positions, or cancel, with a draggable interface.
- **Thumbnail Preview**: Displays a draggable thumbnail of the captured image with swipe-to-save or right-click options.
- **Save Destinations**: Supports saving to Desktop, Documents, Downloads, Clipboard, or opening in Preview.
- **Settings**: Adjust language and reset selection and menu positions via the native settings window (Command + ,).

## 🌍 Multi-Language Support

ScrollSnap currently supports **English, Simplified Chinese, French, German, Japanese, Spanish, and Turkish**.

**Notice a typo or want ScrollSnap in your language?** Contributions are incredibly welcome! As a solo developer, I rely on the community to help make ScrollSnap accessible to everyone.

Whether you want to add a completely new language or improve an existing translation, see [Contributing](#contributing) and feel free to open a Pull Request.

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
- **Contributor note**: If you are building from source, see `Contributing` for local Xcode signing setup.

## Usage

1. **Launch the App**:

- ScrollSnap starts automatically, displaying an overlay with a selection rectangle and menu bar.

2. **Adjust the Selection**:

- Drag the rectangle to move it or use the resize handles to adjust its size.

3. **Capture a Screenshot**:

- For scrolling capture, click "Capture" to start, then "Save" to stop and stitch the images, or press Return or keypad Enter when the overlay is focused.

4. **Interact with the Thumbnail**:

- Drag the thumbnail to copy the image elsewhere, swipe right to save, or right-click for options (Show in Finder, Delete, Close).

5. **Save Options**:

- Use the "Options" menu to set the save destination (Desktop, Clipboard, etc.).

6. **Settings**:

- Press `Cmd + ,` to open the settings window, change language, or reset positions if needed.

7. **Quit**:

- Press `Esc` or select "Quit ScrollSnap" from the main menu.

## Project Structure

```
ScrollSnap
│── App
│   │── ScrollSnapApp.swift         # App entry point (SwiftUI)
│   │── AppDelegate.swift          # Menu and settings setup
│── Utilities
│   │── Constants.swift            # App-wide constants
│   │── ScreenshotUtilities.swift  # Screenshot capture and save logic
│── Views
│   │── OverlayView.swift          # Main overlay coordinator
│   │── SettingsView.swift         # Native SwiftUI settings pane
│   │── ContentView.swift          # Placeholder SwiftUI view
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

### Development Signing

If you are contributing locally in Xcode:

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`.
2. Set your local `DEVELOPMENT_TEAM` in that file.
3. Uncomment `CODE_SIGN_IDENTITY = Apple Development` only if Xcode cannot infer it on your machine.
4. Reopen the project in Xcode and run normally.

macOS tracks Screen Recording permission by signed app identity. Ad-hoc signing can make a rebuilt app look new after each code change, which causes repeated permission prompts. A real local development signature keeps that permission stable across rebuilds.

- **Report Issues**: Open an issue on the [GitHub repository](https://github.com/brkgng/ScrollSnap/issues) for bugs or feature requests.
- **Submit Pull Requests**:
  1. Fork the repo.
  2. Create a new branch for your changes (e.g., `git checkout -b feature/your-feature-name`).
  3. Make your changes and commit them.
  4. Submit a pull request with your improvements.

## License

Licensed under the MIT License. See [LICENSE](LICENSE).
