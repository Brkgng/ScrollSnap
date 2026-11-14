# Project guidance

Code changes must be simple, elegant, and as readable as possible.

## Testing

Choose tests according to the behavior changed:

- Use focused unit tests for individual defects and capture-session state transitions.
- Use image replay tests for stitched-image completeness and correctness. Check content order, output height, and pixel fidelity; successful process completion alone does not establish accuracy.
- Keep a small live UI suite for behavior that requires the real macOS app, such as input routing, repeated capture, thumbnail interaction, and display placement.

Prefer unit and replay tests when they cover the change, since they run without controlling the desktop. Avoid duplicate coverage and keep long repeated-capture stress runs opt-in. Tell the user before live UI automation starts, since it controls the desktop mouse and keyboard.

## Screen Recording permission and signing

- Preserve the project's certificate signing for ScrollSnap app builds and hosted unit tests. Do not use `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGN_IDENTITY=-`, or an empty `DEVELOPMENT_TEAM` for the app. Ad-hoc builds can appear under the same name in System Settings while failing to match the existing permission grant.
- Use the existing `Config/Signing.local.xcconfig` and persistent build paths. If the signing identity is unavailable, report the blocker instead of falling back to ad-hoc signing. Keep Debug and Release bundle identities separate.
- Unit tests must not run the real startup permission request or capture UI. Keep the XCTest launch guard in `AppDelegate`; inject permission responses in permission tests.
- For live capture tests, use the signed app built by `Tests/CaptureBaseline/run.py` or supply a signed `--app-bundle`. The runner rejects uncertified app copies before launching tests. Do not reset macOS permissions as routine test setup.
