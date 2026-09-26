# Summary

Implementation notes that are too detailed for the README.

## Margins

The profile's `margin` (the "Margin" slider) maps linearly to 1–40 screen
pixels over 0–100%. The slider now reaches 300%, and values above 100% extend
that line, so existing profiles keep their look. `verticalMargin` ("Top/bottom
margin") scales that same setting for the top and bottom edges. It defaults
to 100%, and profiles saved without it load as 100%. Both edges also get extra
room derived from the screen radius so text clears rounded corners.

Horizontal margins are applied in terminal-texture pixels, which low-resolution
fonts with a base width of 0.5 (e.g. the DEC VT100 font) stretch to half
width. So at 100% the side margins of such fonts display narrower than the top
and bottom.

## Fixed terminal geometry (`--geom`)

`--geom <rows>x<cols>` (e.g. `24x80`) is parsed in `app/main.cpp` and handed
to QML as the `startupGeometry` context property (width = columns, height =
lines). `fitGeometry()` in `PreprocessedTerminal.qml` then measures the
terminal's actual cell count and adjusts the global `fontScaling` until the
requested size just fits. After that it widens the terminal's
`extraMargin`/`extraVerticalMargin` to trim the surplus cells, which centers
the text. It measures instead of calculating because the count depends on
margins, bitmap-font scaling and QMLTermWidget's own rounding. A debounce timer
waits for each font change to settle before measuring again.

The scaling search starts with proportional guesses, then bisects once one
scaling that fits and one that doesn't are known. Line counts don't scale
exactly inversely with `fontScaling`, so proportional steps alone oscillate.
The fit may exceed `maximumFontScaling`, which only limits manual zoom.

Pitfall: QMLTermWidget's `terminalSize` is `QSize(lines, columns)`, the reverse
of `startupGeometry`.

With `--verbose`, each fit step is logged. Fedora's Qt suppresses debug output
(including QML `console.log`) by default, so run with
`QT_LOGGING_RULES="*.debug=true;qt.*.debug=false"` there.

The fit reruns whenever the terminal area is resized, but not after manual
zooming. Because `fontScaling` is an app-wide setting, the fitted value is
saved on exit like a manual zoom.

## Backspace sends Delete

The per-profile `backspaceSendsDelete` option (Advanced → Miscellaneous)
makes plain Backspace send DEL (0x7f) instead of the ^H that QMLTermWidget's
`default.keytab` sends. A `Keys.onPressed` handler on the terminal item in
`PreprocessedTerminal.qml` intercepts the key and calls
`QMLTermSession.sendText()`, so the submodule and its keytabs stay untouched.
Ctrl, Alt and Meta combinations still go through the keytab (Ctrl+Backspace
already sends DEL there). Profiles without the key load with it off.

## Bundled fonts

Bundled fonts live in `app/qml/fonts/<name>/`. Each is registered with
`addBundledFont()` in `FontManager::populateBundledFonts()`
(`app/fontmanager.cpp`) and listed in `app/qml/resources.qrc`. Low-resolution
fonts (`*_SCALED`) are rendered at their native pixel size and then scaled;
the rest are only offered in the "modern" rasterization mode.

### DEC VT100 (`DEC_VT100_SCALED`)

Generated from the VT100 character ROM (23-018E2) by
`scripts/make_vt100_font.py`; see `app/qml/fonts/dec-vt100/README.md`.

- The cell is 10x10 pixels at a native size of 10px, drawn as grid-aligned
  rectangles at 128 units per pixel (units per em 1280). The power-of-two
  multiple keeps FreeType's scale factor exact; 100 units per pixel yields
  9.984px advances that drift across a line.
- The font carries a no-op `fpgm` program. Without one, FreeType treats the
  font as unhinted and runs its autohinter even under the terminal's
  `PreferFullHinting`, which doubles 1-pixel horizontal lines and turns the
  checkerboard solid. Verify changes by rendering at 10px with Qt,
  `QFont::NoAntialias` and `PreferFullHinting`.
- Each glyph's left side bearing in `hmtx` must equal its `xMin`. The
  bytecode interpreter positions outlines from the bearing, so a zero
  bearing shifts glyphs with a blank left edge (`l`, `i`, `I`, `1`, ...)
  left by that many pixels.
- Box-drawing characters in the terminal are normally drawn by
  QMLTermWidget's own line renderer, not by the font.

Used by the built-in "DEC VT100" profile in `app/qml/ApplicationSettings.qml`.

### Glass TTY VT220 (`GLASS_TTY_VT220`)

svofski's VT220-style font (https://github.com/svofski/glasstty), public
domain, bundled unmodified as a high-resolution font.
