# Project guidance

Code changes must be simple, elegant, and as readable as possible.

## Testing

Choose tests according to the behavior changed:

- Use focused unit tests for individual defects and capture-session state transitions.
- Use image replay tests for stitched-image completeness and correctness. Check content order, output height, and pixel fidelity; successful process completion alone does not establish accuracy.
- Keep a small live UI suite for behavior that requires the real macOS app, such as input routing, repeated capture, thumbnail interaction, and display placement.

Prefer unit and replay tests when they cover the change, since they run without controlling the desktop. Avoid duplicate coverage and keep long repeated-capture stress runs opt-in. Tell the user before live UI automation starts, since it controls the desktop mouse and keyboard.
