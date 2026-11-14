# Tutorial demo assets

The bundled silent movies are 14-second demonstrations rendered at 1600 × 1040,
24 fps. They use the production `SelectionRectangleView` and `MenuBarView` drawing
code over a neutral sample page. A drawing-only fixture supplies rectangle and
capture state; generation does not capture the screen, access personal content,
write app preferences, or move the desktop mouse or keyboard.

After a signed Debug build, regenerate with Swift and ffmpeg installed:

```sh
python3 Tests/TutorialDemo/render.py --app-bundle "/path/to/ScrollSnap Dev.app"
```

Use `--locales en` to preview one language. The source app supplies the localized
toolbar strings. Output goes to `ScrollSnap/Resources/TutorialDemo/`.

Keep the action timings synchronized with `CaptureTutorialStep`: selection until
4.5 seconds, manual scrolling until 10 seconds, then Save and the combined result.
Captions are native localized text layered over the movie. The PNGs provide a
still image while loading and when Reduce Motion is enabled.
