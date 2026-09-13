# Status Trio

**Three system signals. One native macOS menu bar icon.**

Status Trio is a native macOS menu bar app that combines battery, Wi-Fi, and volume into one compact three-in-one status icon. It is inspired by the iPhone Duo's compact multi-status icon direction, but adapted for the Mac by replacing cellular signal with volume.

> Status Trio is an independent project and is not affiliated with Apple.

## Features

- One configurable 20–32 pt menu bar icon (default 28 pt) for battery, Wi-Fi, and volume.
- Settings window to adjust the icon render size and language, applied live and persisted.
- Battery percentage and charging bolt with independent visibility controls.
- Configurable battery number/bolt size and optional arc status colors.
- Charging state, estimated time to full, Low Power Mode, and a Battery Settings shortcut.
- Wi-Fi signal strength, current network name, and common network states.
- System output volume and mute state.
- Left-click popover with current status details.
- Native right-click menu with version and quit actions.
- Event-driven updates with a low-frequency polling fallback.
- Twelve languages with system-language following and an immediate in-app override.

## Languages

Status Trio follows the macOS preferred language by default and supports English, Simplified Chinese, Traditional Chinese, Japanese, Korean, Spanish, French, German, Italian, Brazilian Portuguese, Russian, and Arabic. Open Settings to choose a language manually; changes apply immediately without restarting the app.

## Status

Status Trio is implemented as a Swift Package. See Development and Build a local app bundle below for the current commands.

## Specification

- [Status Trio design specification](docs/superpowers/specs/2026-09-12-status-trio-design.md)

## Technical baseline

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` menu bar app
- No App Sandbox or network permission. Location permission is optional and requested only when the user chooses to show the current Wi-Fi network name.

## Reference design

- [SVG source](status-menubar.svg)
- [Data-driven demo](status-menubar-demo.html)

## Development

Run the test suite:

```bash
swift test
```

An optional XCTest filter can be passed through the test helper:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Run the app directly from the Swift package:

```bash
swift run StatusTrio
```

## Build a local app bundle

Build an ad-hoc-signed local app bundle:

```bash
bash scripts/build-app.sh release
```

This creates `dist/StatusTrio.app` and opens it by default. In open mode, the script asks any existing instance with the same bundle identifier to quit and waits briefly before launching the freshly built bundle. Pass `no-open` as the second argument to only build without quitting or launching an app:

```bash
bash scripts/build-app.sh release no-open
```

To run a worktree build alongside the main app, override its bundle identifier and display name:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.batteryIndicatorsSettings APP_NAME="Status Trio (Battery Indicators)" bash scripts/build-app.sh release open
```

The single-instance lock is scoped by bundle identifier, so differently identified builds can run at the same time. Main builds keep using `com.lingsmbp.StatusTrio` by default; no bundle identifier change is required before merging.

The ad-hoc-signed bundle is intended for local personal use. Gatekeeper may reject it if the bundle is transferred with quarantine metadata.
