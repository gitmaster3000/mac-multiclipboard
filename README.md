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

## Picker panel

Press **⌘⌥V** from any app (or pick *Show Clipboard History* in the menu) to open
the floating picker. Keyboard shortcuts inside the panel:

| Key | Action |
| --- | --- |
| ↑ / ↓ | Move selection |
| ⏎ | Paste the selected clip into the previously frontmost app |
| ⌫ | Delete the selected clip (⌘⌫ while the search field has focus) |
| ⌘F | Focus the search field |
| Esc | Dismiss the panel |

The panel also closes as soon as it loses key focus. Pasting synthesizes a ⌘V
keystroke, which needs Accessibility permission
(System Settings → Privacy & Security → Accessibility). Without it the clip is
still copied to the pasteboard, it just isn't auto-pasted.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcut registration, wired via SwiftPM.
