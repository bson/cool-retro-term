# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

cool-retro-term is a Qt6/QML terminal emulator that mimics old CRT screens. The terminal emulation itself comes from `qmltermwidget` (a QML port of Konsole's qtermwidget, a git submodule on its `unstable` branch). Single-instance behaviour comes from `KDSingleApplication` (also a submodule). Targets are Linux and macOS.

## Build and run

Requires Qt 6 with the `qt5compat` and `qtshadertools` modules (`qsb` must be available). The build uses qmake. There is no CMake build yet.

```sh
git submodule update --init --recursive   # both submodule dirs are empty until this runs
mkdir -p build && cd build
qmake ../cool-retro-term.pro
make -j"$(nproc)"
./cool-retro-term                          # binary lands in the build root; qmltermwidget/ is found next to it
./cool-retro-term --default-settings --verbose   # ignore stored settings, log profile/settings JSON
```

Rerunning `qmake` in an existing build dir only regenerates the top-level Makefile. `app/Makefile` keeps its old `APP_VERSION` define, and qmake doesn't track define changes. To get the current `git describe` version into the binary, run `make qmake_all`, delete `app/main.o`, then `make`.

Packaging: `scripts/build-appimage.sh` (Linux, uses linuxdeploy) and `scripts/build-dmg.sh` (macOS, uses macdeployqt). CI (`.github/workflows/release.yml`) runs both of these on pushes to master and on tags. There are no tests and no lint setup.

## Architecture

**Startup (C++ → QML).** `app/main.cpp` handles CLI args (`-e`, `--workdir`, `-p/--profile`, `--fullscreen`, …). It registers the C++ types `FontManager` and `FontListModel` under the `CoolRetroTerm` QML module. It exposes the context properties `fileIO`, `workdir`, `defaultCmd`, `defaultCmdArgs` and `appVersion`, then loads `qrc:/main.qml`. A second launch sends `"new-window"` via KDSingleApplication, and the primary instance calls `createWindow()` on the QML root.

**QML object tree.** `main.qml` is a non-visual `QtObject` root that owns shared singletons: `appSettings` (ApplicationSettings), `timeManager`, `settingsWindow`, `aboutDialog`, and a `windowsModel` of open windows. The nesting below each window is:
`TerminalWindow` → `TerminalTabs` → `TerminalContainer` (which *is* a `ShaderTerminal`) → `PreprocessedTerminal` (wraps `QMLTermWidget`, plus a `ShaderEffectSource` and `BurnInEffect`). `TerminalFrame` draws the bezel. Many components use `appSettings`, `timeManager`, etc. directly by id, as context globals, instead of passing them as properties.

**Settings and profiles** live in `app/qml/ApplicationSettings.qml`. They are saved as JSON strings in a SQLite DB via `Storage.qml` (QtQuick.LocalStorage), under the keys `_CURRENT_SETTINGS`, `_CURRENT_PROFILE` and `_CUSTOM_PROFILES`. App-wide settings and per-profile appearance settings are handled separately:
- To add a new profile property, you must update **both** `composeProfileObject()` and `loadProfileString()`. Recent bug fixes came from missing one of them.
- In `loadProfileString()`, order matters: `fontSource` must be assigned before `fontName`, because FontManager's font lookup depends on the source.
- Built-in profiles are `ListElement`s in `profilesList` that hold an `obj_string` JSON blob. Custom profiles are the non-`builtin` entries.
- Font properties (`fontName`, `fontSource`, `rasterization`, `fontWidth`, `lineSpacing`, `fontScaling`) are aliases onto the C++ `FontManager` (`app/fontmanager.cpp`). FontManager filters bundled fonts versus system fonts based on the rasterization mode. Rasterization 4 is "modern".

**Bundled fonts** live under `app/qml/fonts/`. To add one, register it with `addBundledFont(...)` in `fontmanager.cpp` **and** list the file in `app/qml/resources.qrc`. `DEC-VT100.ttf` is generated from a ROM dump by `scripts/make_vt100_font.py`. Regenerate it with that script rather than editing the TTF. SUMMARY.md explains the hinting pitfall it works around.

**Shaders.** The CRT effect has two passes in `ShaderTerminal.qml`: a *dynamic* pass (per-frame: noise, flicker, rasterization, burn-in) and a *static* pass (RGB shift, bloom, curvature, frame shine). To avoid runtime branching, `app/app.pro` compiles `terminal_dynamic.frag` and `terminal_static.frag` into one `.qsb` variant per combination of `-DCRT_*` feature flags. `dynamicFragmentPath()` and `staticFragmentPath()` in `ShaderTerminal.qml` then choose the variant at runtime from the current settings. Pitfalls:
- The compiled `.qsb` files are written into `app/shaders/` in the **source tree**, are committed, and must each be listed in `resources.qrc`. Adding a feature flag means updating the loops in `app.pro`, the path builder in `ShaderTerminal.qml`, and the qrc list together.
- `terminal_static_*_chroma*` `.qsb` files in `app/shaders/` are leftovers that the current build doesn't produce and the qrc doesn't reference.
- Other shaders (`burn_in`, `terminal_frame`, the `.vert` files) are compiled one-to-one by the generic `qsb` extra compiler.

**Adding a setting to the UI.** Declare the property in `ApplicationSettings.qml`, persist it in the matching compose/load pair (settings or profile), and add a control in one of the `Settings*Tab.qml` files. Window-level actions and shortcuts live in `TerminalWindow.qml`. The menus are in `app/qml/menus/`.
