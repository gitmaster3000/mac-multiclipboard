# Multiclipboard

Menu-bar clipboard manager for macOS.

## Screenshots

| Clipboard history | Settings |
| --- | --- |
| <img src="docs/screenshots/clipboard-history.png" alt="Clipboard history in light mode with search, image previews, pinning, and delete controls" width="380"> | <img src="docs/screenshots/settings.png" alt="Settings showing picker and screenshot shortcuts, pin placement, System, Light, and Dark appearance options, and launch at login" width="338"> |
| Search and paste saved text and images, pin entries, or remove clips. | Customize screenshot shortcuts, appearance, pin placement, and launch at login. |

## Requirements

- macOS 14+
- Xcode 15+ (or Swift 5.9+ command line tools)

## Build & run

For setup instructions, command-line and Xcode workflows, verification, and
troubleshooting, see [Running Multiclipboard](docs/RUNNING.md).

To run the app with a persistent Accessibility permission (needed for automatic
paste-back), build and launch its app bundle:

```bash
./Scripts/make_app.sh
open Multiclipboard.app
```

`swift run` is useful during development, but it launches a bare executable
whose Accessibility grant cannot be retained by macOS.

`make_app.sh` automatically uses an installed code-signing identity so the
grant survives rebuilds. On a machine without one, it falls back to ad-hoc
signing and prints a warning; macOS ties that grant to the current binary, so
it must be granted again after rebuilding. Set `MULTICLIP_SIGNING_IDENTITY` to
choose a specific identity.

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
still copied to the pasteboard, it just isn't auto-pasted. If permission is
missing or has become stale, the app explains how to restore it and can open
the correct System Settings pane directly.

Entries are ordered newest-first within pinned and unpinned groups. Use the pin
button on a row to protect important entries, and choose whether pins appear at
the top or bottom in Settings. Rows and the context menu include Delete, while
the picker toolbar includes a confirmed Remove All action.

## Clip actions

Each row's context menu and its *More* menu expose per-clip actions:

- **Rename / Edit Name** — give a clip a custom title. For images pasted into
  Finder, the title becomes the file name.
- **View / Edit Text** — open a text clip in an editable overlay.
- **Save Image to Downloads** — write an image clip to your Downloads folder.
- **Save as Prompt** — promote a text clip into the Prompt Library.
- **Share** — send a clip through the macOS share sheet.

Pasting an image while Finder is frontmost drops it to a temporary file and
puts that file on the pasteboard, so ⌘V materializes a real image file rather
than nothing.

## Prompt Library

Enable the Prompt Library in Settings to add a second tab to the picker for
reusable text snippets. Add, edit, delete, and search prompts, then paste one
the same way you paste a clip.

## Screenshot shortcuts

Configure shortcuts in Settings that open Apple's area selector — or capture the
full screen — and copy the result straight into clipboard history, ready to
paste from the picker.

## History retention

Set how long text and rich text, images, and files are kept before they are
automatically evicted. Each type has its own retention duration, configured in
Settings. Pinned entries are never evicted.

## Appearance and launch

Choose a System, Light, or Dark appearance, decide whether pinned entries sit at
the top or bottom of the list, and enable Launch at Login so Multiclipboard
starts with your session — all in Settings.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — global keyboard shortcut registration, wired via SwiftPM.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes.
