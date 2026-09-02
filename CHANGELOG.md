# Changelog

All notable changes to Multiclipboard are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses semantic versioning.

## [1.4.1]

### Fixed

- Pasting an image into Finder now works for every clip, not only ones you had
  renamed. A frontmost-app check that ran while the picker was key meant the
  file-name prompt for unnamed images never fired reliably; the prompt is gone
  and the clip's existing title is used as the file name instead.
- The About window now reads its version from the app bundle instead of a
  hard-coded string, so it always matches the packaged version.

## [1.4.0]

### Added

- **Prompt Library** — a second tab in the picker for reusable text snippets.
  Add, edit, delete, search, and paste prompts, and promote any text clip to a
  prompt with *Save as Prompt*. Toggle the tab in Settings.
- **Screenshot shortcuts** — configurable shortcuts that open Apple's area
  selector and copy the capture straight into history, plus a full-screen
  capture shortcut.
- **History retention** — set how long text, images, and files are kept before
  automatic eviction, independently per type, in Settings.
- **Clip actions** — rename a clip, view and edit the text of a text clip,
  save an image to Downloads, and share a clip via the macOS share sheet, all
  from the row's context and *More* menus.
- **Appearance and placement** — choose System, Light, or Dark appearance, and
  whether pinned entries sit at the top or bottom of the list.
- **Launch at login** — start Multiclipboard automatically when you log in.
