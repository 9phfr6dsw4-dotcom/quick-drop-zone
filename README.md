# Quick Drop Zone

Quick Drop Zone is a native SwiftUI/AppKit menu-bar utility for macOS 26 and newer. Drop a file into its popover, choose a favorite folder, and confirm the move. It has no Dock icon.

## Features

- Favorite folders are selected in a native folder picker and stored as security-scoped bookmarks.
- File moves require an explicit destination-button click. The latest move can be undone.
- Suggestions obey extension rules exactly. Screenshot detection checks macOS's screen-capture metadata and uses `Screenshot… .png` names only as a fallback. Learning requires at least three distinct same-extension examples with a shared meaningful subject; weak matches produce no suggestion. Every suggestion includes a reason.
- Cleanup reviews visible, top-level regular files in Downloads or any folder you choose. You can change destinations, uncheck files, and approve a batch.
- Unassigned files are grouped only when their filenames share a specific subject. Groups are unchecked and show the editable folder name, reason, and the folder being cleaned as the creation location. The folder is created only after approval; Undo restores the files and removes the new folder only if it is app-created and empty.
- The on-device model is not used as a destination fallback; uncertain files remain unsorted rather than receiving a guess.
- Trash suggestions have a separate review section and are unchecked by default. The app only allows a matching `.dmg` installer directly in Downloads when the matching `.app` bundle is directly in `/Applications`. Moving to Trash uses macOS Trash; the app never permanently deletes files or empties Trash.
- No file contents are read, and the app has no networking or analytics code.

## Download and open

1. Open the [v1.1.0 release page](https://github.com/9phfr6dsw4-dotcom/quick-drop-zone/releases/tag/v1.1.0).
2. Download `Quick-Drop-Zone-1.1.0.zip` from **Assets** and unzip it.
3. Move **Quick Drop Zone.app** to **Applications**.
4. The app is ad-hoc signed, not notarized. The first time, Control-click **Quick Drop Zone.app**, choose **Open**, then choose **Open** again.
5. Look for the tray/download icon in the menu bar. Click it to open the drop window. Use **Settings** to add favorite folders.

## Build and test

Requires Xcode with the macOS 26 SDK:

```bash
swift test
bash Scripts/package-app.sh
bash Scripts/smoke-test.sh
```

GitHub Actions uses the standard `macos-26` runner, checks the installed Xcode and SDK, runs the core tests, packages a `.app`, verifies the executable after extracting the exact ZIP, and smoke-launches the app. The downloadable ZIP is uploaded as a run artifact.

## Privacy

Preferences and learned filename tokens are stored in this Mac’s `UserDefaults`. Screenshot metadata and file names are read locally. No files, file names, or metadata are sent online; the app does not use an AI service to guess destinations.
