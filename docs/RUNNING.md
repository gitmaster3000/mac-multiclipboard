# Running Multiclipboard

Multiclipboard is a macOS menu-bar application built as a Swift package. It
runs without a Dock icon and keeps the terminal process open while it watches
the system clipboard.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 15 or newer, including the Xcode command-line tools
- Swift 5.9 or newer

Confirm that Swift is available:

```bash
swift --version
```

If macOS cannot find the developer tools, install them with:

```bash
xcode-select --install
```

## Run from Terminal

From the repository root, resolve dependencies, build, and run the app:

```bash
swift package resolve
swift build
swift run
```

After the build completes, a clipboard icon appears in the macOS menu bar. The
process remains attached to the terminal; this is expected. Use the menu-bar
icon's **Quit** item to stop the app cleanly.

The shorter command below is enough after the initial setup because SwiftPM
builds automatically when required:

```bash
swift run
```

## Run from Xcode

Open the package directly:

```bash
open Package.swift
```

In Xcode:

1. Select the **MenuBarClipboard** scheme.
2. Select **My Mac** as the run destination.
3. Choose **Product → Run**, or press `Command-R`.
4. Look for the clipboard icon in the macOS menu bar.

Stop the app with its **Quit** menu item or Xcode's stop button.

## Verify the clipboard monitor

With the app running:

1. Copy plain text from any application.
2. Copy rich text from an editor such as TextEdit.
3. Copy an image.
4. Copy one or more files in Finder.

The current milestone stores these entries in the history database. It does not
yet expose the stored history in the menu; that UI belongs to a later
milestone.

The monitor checks `NSPasteboard.general.changeCount` every 500 milliseconds.
It ignores concealed and transient clipboard items, deduplicates equal content,
and retains at most 200 entries while preserving pinned entries.

## History location

SwiftData persists clipboard history under:

```text
~/Library/Application Support/Multiclipboard/History.store
```

The history remains available after quitting and restarting the application.

## Run tests

Run the complete test suite from the repository root:

```bash
swift test
```

The tests cover text, RTF, image and file-URL extraction; concealed and
transient exclusions; SHA-256 deduplication; capacity eviction; timer
lifecycle; and reopening a persistent SwiftData store.

For a production-configuration build, run:

```bash
swift build -c release
```

## Troubleshooting

### The menu-bar icon does not appear

- Confirm that the build process is still running.
- Check the right side of the menu bar and its hidden-items area.
- Quit any older Multiclipboard process before launching another copy.

### The project requires a newer macOS version

SwiftData requires macOS 14 for this package. Confirm the active deployment
environment with `sw_vers` and update macOS if necessary.

### Swift uses the wrong Xcode installation

Inspect the active developer directory:

```bash
xcode-select -p
```

If multiple Xcode versions are installed, select the intended version in
Xcode's **Settings → Locations → Command Line Tools**.
