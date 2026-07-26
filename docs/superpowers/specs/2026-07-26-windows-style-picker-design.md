# Windows-style clipboard picker

Date: 2026-07-26

## Problem

The picker panel works but does not feel like the Windows `Win+V` clipboard
history it is modelled on:

- The shortcut is hard-coded. Changing it means editing `AppDelegate` and
  rebuilding. This matters more than usual here, because a combo can be
  silently swallowed by another process's event tap, and the only recourse is
  to pick a different one.
- The panel opens centred on the screen. `Win+V` opens at the pointer.
- At 720x420 with a split list/preview layout, the panel is far larger than the
  task needs.

## Goals

1. Let the user set the shortcut from a settings window, with changes applied
   immediately.
2. Open the panel at the cursor, clamped to the screen it is on.
3. Replace the split pane with a single compact column.

Paste-back behaviour is unchanged: Return puts the clip on the pasteboard and
synthesises Cmd+V into the previously frontmost app.

## Design

### Shortcut preference

`ShortcutPreference` is a value type holding a Carbon key code and Carbon
modifier mask, plus `UserDefaults` persistence under `pickerShortcut`.

```swift
struct ShortcutPreference: Equatable {
    var carbonKeyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = ShortcutPreference(kVK_ANSI_V, cmdKey | optionKey)
}
```

It stores Carbon values rather than `NSEvent.ModifierFlags` because that is
what `RegisterEventHotKey` consumes and what `HotKey`'s `KeyCombo` exposes, so
no lossy conversion sits between the stored value and registration.

A shortcut is rejected if it carries none of Command, Control, or Option.
Single-key and Shift-only global hot keys would fire while typing.

### Registration and failure reporting

`AppDelegate` keeps ownership of the `HotKey` instance and gains
`applyShortcut(_:)`, which drops the existing instance and registers the new
one.

`HotKey` discards the `RegisterEventHotKey` status code, so a combo that fails
to register is indistinguishable from one that works. The settings window
therefore verifies a candidate before saving it: it calls
`RegisterEventHotKey` directly, records whether the status was `noErr`, then
unregisters. On failure the recorder reports that the combo is unavailable and
keeps the previous shortcut.

Registration status alone is not enough. A combo consumed by an event tap
upstream of Carbon registers with `noErr` and still never fires — this is what
happened to Cmd+Shift+V, which Siri's event taps swallow. Checking the status
code would have reported success for a shortcut that was completely dead.

So the recorder confirms the whole path, not just registration. After a combo
records successfully, the settings window enters a confirmation state:

1. The candidate shortcut is registered with a temporary handler.
2. The window asks the user to press the combo.
3. If the handler fires, the shortcut is saved and applied.
4. If nothing fires within 10 seconds, the window reports that the combo does
   not reach the app and suggests a different one. The previous shortcut is
   kept.

The user can skip the confirmation and save anyway, for the case where they
are setting a shortcut they cannot press right now.

This is the only way to detect a tap-swallowed combo from inside the app;
there is no API that reports which process consumed a keystroke.

### Panel placement

`PanelPlacement` is a pure function so it can be tested without a window:

```swift
enum PanelPlacement {
    static func origin(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint
}
```

The panel is placed below-right of the cursor, matching `Win+V`, then clamped
so it stays inside `visibleFrame`. Near the right edge it flips to the left of
the cursor; near the bottom it flips above. `ClipPickerPanelController.show()`
picks the screen containing the cursor and calls this instead of
`panel.center()`.

Coordinates stay in AppKit's bottom-left origin space throughout; no flipping
is done, since `NSEvent.mouseLocation` and `NSScreen.visibleFrame` already
share that space.

### Compact panel

The panel becomes 340x420, single column, borderless with rounded corners and
no title bar.

Each row is a fixed 36pt: kind icon, one-line snippet, relative timestamp
trailing. Image rows show a small inline thumbnail in place of the icon.

`previewColumn` and the `plainText(fromRTF:)` helper it used are removed. The
snippet already carries the plain-text preview, so nothing else needs them.

### Settings window

`SettingsWindowController` hosts a SwiftUI view with the recorder field and a
"Reset to default" button. The menu bar menu gains "Settings…" bound to Cmd+,.

The recorder is an `NSViewRepresentable` wrapping an `NSView` that becomes
first responder on click and captures `keyDown`. Modifier-only presses are
ignored so the field waits for a real key. Escape cancels recording.

## Testing

`ShortcutPreference`

- round-trips through `UserDefaults`
- falls back to the default when the stored value is absent or malformed
- rejects combos with no Command, Control, or Option

`PanelPlacement`

- cursor mid-screen places the panel below-right
- cursor near the right edge flips the panel left of the cursor
- cursor near the bottom edge flips the panel above the cursor
- cursor in a corner satisfies both constraints and stays inside the frame

`ShortcutConfirmation` (the state machine behind the confirm step)

- starts idle, moves to awaiting on a recorded combo
- moves to confirmed when the handler reports a fire
- moves to failed when the deadline passes with no fire
- a fire arriving after failure does not resurrect the confirmed state

The state machine is separated from the window so it can be driven by an
injected clock in tests rather than a real 10-second wait.

The recorder view and settings window themselves are not unit tested; they are
thin wrappers over AppKit first-responder behaviour with no logic worth
asserting in isolation.

## Out of scope

- Pinning entries. `ClipEntry.pinned` exists and eviction respects it, but no
  UI exposes it. Unchanged here.
- Multiple shortcuts, or a separate shortcut for paste-plain-text.
- Any change to capture, storage, or eviction.
