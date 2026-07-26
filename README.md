# Multiclipboard

Menu-bar clipboard manager for macOS.

## Requirements

- macOS 14+
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
It polls the system pasteboard every 500 ms and persists text, rich text,
images, and file URLs in a SwiftData history store.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcut registration, wired via SwiftPM.
