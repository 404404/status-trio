# Status Trio

**Three system signals. One native macOS menu bar icon.**

Status Trio is a native macOS menu bar app that combines battery, Wi-Fi, and volume into one compact three-in-one status icon. It is inspired by the iPhone Duo's compact multi-status icon direction, but adapted for the Mac by replacing cellular signal with volume.

> Status Trio is an independent project and is not affiliated with Apple.

## Planned features

- One 20 pt menu bar icon for battery, Wi-Fi, and volume.
- Battery percentage, charging state, and Low Power Mode.
- Wi-Fi signal strength and common network states.
- System output volume and mute state.
- Left-click popover with current status details.
- Native right-click menu with version and quit actions.
- Event-driven updates with a low-frequency polling fallback.

## Status

The project is currently in the design phase. The implementation plan and app source will follow after the specification is reviewed.

## Specification

- [Status Trio design specification](docs/superpowers/specs/2026-09-12-status-trio-design.md)

## Technical baseline

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` menu bar app
- No App Sandbox, network permission, or location permission
