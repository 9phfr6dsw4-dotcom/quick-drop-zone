# Quick Drop Zone

Quick Drop Zone is a native SwiftUI/AppKit menu-bar utility for macOS 26 and newer. Drop a file into its popover, choose a favorite folder, and confirm the move. It has no Dock icon.

## Features

- Favorite folders are selected in a native folder picker and stored as security-scoped bookmarks.
- File moves require an explicit destination-button click. The latest move can be undone.
- Suggestions use editable extension/filename rules, locally stored learning tokens, and built-in filename/type matches.
- Cleanup reviews visible, top-level regular files in Downloads or any folder you choose. You can change destinations, uncheck files, and approve a batch.
- Unassigned files can be grouped into proposed folders such as `Screenshots` or `PDFs 2025`. Proposed folders are unchecked and are created only after approval inside a favorite folder you select.
- Apple Foundation Models is used only when available. It receives the filename and allowed favorite folder names, runs on-device, and may only select an existing favorite. Rules and learning continue to work when the model is unavailable.
- Trash suggestions have a separate review section and are unchecked by default. The app only allows a matching `.dmg` installer directly in Downloads when the matching `.app` bundle is directly in `/Applications`. Moving to Trash uses macOS Trash; the app never permanently deletes files or empties Trash.
- No file contents are read, and the app has no networking or analytics code.

## Download and open

1. Open the repository’s **Actions** tab and select the latest successful **macOS CI** run.
2. Download the `Quick-Drop-Zone-<run number>` artifact and unzip it.
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

Preferences and learned filename tokens are stored in this Mac’s `UserDefaults`. Foundation Models is Apple’s on-device framework; no file name or file content is sent to an online service by this app. The model is optional and guarded by its runtime availability.
