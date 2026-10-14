# Capture baseline

This separate harness exercises production capture code without adding product test hooks.
Keep each completed run in its own directory, then reuse the same fixtures after improvements.

## Image replay

From the repository root:

```sh
python3 Tests/CaptureBaseline/run.py --output /private/tmp/scrollsnap-before
```

The runner compiles the production matcher and stitcher with Swift 5 language mode and Release optimization. It generates numbered rows with machine-readable markers, then records:

- Static, tiny, slow, normal, fast, reverse, reverse-and-resume, pinned-header, and animation scenarios.
- Three timing trials at both 1x and 2x scale: 54 observations across the nine scenarios.
- Six additional conversation-image checks: normal, fast, and a deliberately missing overlap, once at each scale.
- Expected and actual PNGs, row order, height, pixel mismatch, processing time, and process CPU time.

Run after improvements, on the same Mac and macOS version:

```sh
python3 Tests/CaptureBaseline/run.py --output /private/tmp/scrollsnap-after --compare /private/tmp/scrollsnap-before
```

`report.md` describes each run. `comparison.md` compares content completeness, pixel fidelity, and median processing time separately. The runner refuses to overwrite completed results and checks fixture hashes and environment before comparing. `metadata.json` records the app and test-source hashes.

Recording a baseline deliberately succeeds even when image expectations fail; consult `accurate` in `observations.json` and the report. The executable also accepts `--check` to exit nonzero for failed expectations. Infrastructure failures, such as unavailable Vision services, stop the runner and do not become quality measurements.

Image accuracy requires the expected height, exact row order, and at most 2% mismatched pixels after normalization to points. Pixel channels tolerate differences up to 12 for rasterization/color conversion. The changing animation region is excluded from pixel comparison. Rows obscured by the initial pinned header are excluded from expected content. Reverse scenarios require the furthest captured extent to be preserved.

`ConversationFixture.swift` generates a neutral conversation-style document (789x3794 pixels), with text, message bubbles, and cards. No private screenshots are stored or bundled by the test harness. Conversation replay uses a 539-point viewport and 80/400-point sampled advances. Each 64-row band must have at most 2% mismatched visible-detail pixels, so the large dark background cannot conceal a missing text line. The gap case jumps beyond one viewport: its expected result is the unchanged initial viewport with `actualIncomplete: true`, not a complete document. All replay scenarios check the expected incomplete state. The conversation checks run once per scale rather than repeating equivalent captures for timing.

Replay positions represent already-sampled frames, not native scroll speed. This cannot establish actual screen sampling, input routing, or UI responsiveness. Timing excludes fixture generation, validation, and image export. Memory is not measured.

## macOS UI tests

Build the development app and test runner without launching them:

```sh
python3 Tests/CaptureBaseline/run.py --mode ui-build --output /private/tmp/scrollsnap-ui-build
```

Run the actual app workflows:

```sh
python3 Tests/CaptureBaseline/run.py --mode ui --output /private/tmp/scrollsnap-ui-before
```

The separate Xcode project runs on macOS, not an iOS simulator. It launches a fixture on the primary display with a 480x400 point viewport and 60 numbered rows, then uses XCUITest to exercise ScrollSnap's existing Return/Escape controls. Nine default tests cover partial-result thumbnail interaction on up to two connected displays, complete scrolling recovery after a clipboard notice or cancellation, scripted captures at 160/640/1600 points per second, native scrolling through the overlay, three normal-speed captures without restarting ScrollSnap, horizontal bands/gradient captures beneath a textured fixed header, and the generated conversation document. The normal-speed sequence first verifies the fixture's visible rows. Every complete numbered-document capture checks all 60 rows in order and output height. Readiness and completion use condition-based waits. Captured images are attached before content assertions; failures stop the current test.

`testConversationCaptureAtNormalAndFastSpeeds` displays the generated conversation image at its native size in a 789x539 point viewport, without bitmap smoothing. This bitmap fixture scrolls in whole-point steps to avoid resampling its one-pixel-per-point source at fractional positions; the other fixtures retain native fractional scrolling. Both speeds (640/1600 points per second) must capture the entire image, pass the same per-band pixel comparison as replay, and show no incomplete notice. The checker allows one point of height rounding and clips any extra bottom pixels before normalization instead of stretching the whole image. Select it with `--only-test testConversationCaptureAtNormalAndFastSpeeds`. This exercises the real capture pipeline against conversation-style visual content; it does not reproduce Codex's live layout changes, delayed text rendering, or trackpad momentum. Record the selected-area frames of a failing live run to investigate those differences.

`testPinnedHeaderCapturePreservesBandsAndGradient` runs both vertical-detail variants on the primary display. They use a 480x100 point viewport with a 20-point fixed header, scrolling by 40 points for bands and 20 for the gradient. The body contains no text or horizontal markers that could hide the matching defect. The test checks output height, one fixed-header marker, known body colors in order, and absence of an incomplete notice. Body samples lie inside bands and allow the existing 12/255 channel tolerance for display color conversion. Select it with `--only-test testPinnedHeaderCapturePreservesBandsAndGradient`.

The fixture has its own bundle identity. ScrollSnap is built in Debug configuration with its existing development identity, rather than launching the installed App Store app. Launch arguments provide the test rectangle, English labels, and Clipboard destination without adding product test hooks. Rectangle arguments use XML property lists so their values remain numeric. Tests restore clipboard contents in teardown. Stop any existing ScrollSnap development run in Xcode first; a competing build with the same bundle ID blocks the baseline. The repeated-session test reopens the menu bar app through macOS's application-open API, matching a Finder reopen, and checks that the process ID stays unchanged.

macOS must allow the Xcode UI test helper to automate the desktop and must grant Screen Recording to the development ScrollSnap app. The runner does not grant or reset permissions. Missing permissions are blockers, not successful tests. Skipped tests make the wrapper report an incomplete UI baseline. `ui.xcresult` contains test results, failures, and exported-image attachments.

Prefer a normally signed Xcode development build with `--app-bundle` for live capture tests. The convenience build uses ad-hoc signing, which can lose permission when its signature changes. Different copies may all appear as “ScrollSnap” in System Settings while access applies to one signing identity. Apple documents this development issue in [its ScreenCaptureKit forum](https://developer.apple.com/forums/thread/819406).

For subsequent UI runs, `--app-bundle "/absolute/path/ScrollSnap Dev.app"` selects an already-built development app. Otherwise the wrapper rebuilds current sources. For a supplied Release build, also pass `--app-configuration Release`; the fixture and UI test helper still use Debug. When testing an older source snapshot, pass `--app-source-root /absolute/path/to/snapshot` so the recorded production hashes describe that app. `--only-test testSlowCapture` selects one test. Build products use a stable temporary path to avoid changing the app location between runs. Metadata records the selected app's identity, version, and executable hash alongside production source hashes. Logs and results remain under the chosen output directory, including summaries when tests fail. The wrapper checks for other Xcode builds and does not terminate unrelated processes.

## Before shipping improvements

Replay measurements use Release optimization. Use supplied Release apps for live comparisons, keeping the app configuration, test sources, and machine consistent between runs. Profile full-app CPU/memory and responsiveness separately. Validate supported older macOS versions, Intel hardware, external displays, and display changes on those machines; this runner does not simulate that hardware or measure memory.

The unit text regressions also render neutral content with CoreText instead of loading screenshots. One varies subpixel text placement; the other repeats a text column across otherwise different sections to reject a false reverse match. Generated capture PNGs belong in the chosen results directory, outside the repository. Keep the test sources tracked.
