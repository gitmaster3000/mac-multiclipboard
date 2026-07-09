# Multiclipboard

Menu-bar clipboard manager for macOS.

## Requirements

- macOS 13+
- Xcode 15+ (or Swift 5.9+ command line tools)

## Build & run

The project is a Swift Package (SwiftPM), which Xcode opens natively as a project:

```bash
open Package.swift   # opens in Xcode
```

Or from the command line:

```bash
swift build
swift run
```

The app launches as a menu-bar accessory (no Dock icon) with a status item.
Click it for the placeholder menu (About, Quit).

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcut registration, wired via SwiftPM.
