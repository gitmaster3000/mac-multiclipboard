# Multiclipboard

Menu-bar clipboard manager for macOS.

## Requirements

- macOS 14+
- Xcode 15+ (or Swift 5.9+ command line tools)

## Build & run

For setup instructions, command-line and Xcode workflows, verification, and
troubleshooting, see [Running Multiclipboard](docs/RUNNING.md).

The quickest way to launch from this directory is:

```bash
swift run
```

The app launches as a menu-bar accessory (no Dock icon) with a status item.
It polls the system pasteboard every 500 ms and persists text, rich text,
images, and file URLs in a SwiftData history store.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcut registration, wired via SwiftPM.
