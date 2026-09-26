<p align="center">
  <img src="docs/images/quick-drop-zone-icon.png" width="88" alt="Quick Drop Zone app icon">
</p>

<h1 align="center">Quick Drop Zone</h1>

<p align="center">A careful, local-first file organizer in the macOS menu bar.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/quick-drop-zone/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+</p>

<p align="center"><a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a></p>

## Review before anything moves

Cleanup suggestions stay visible until you approve them.

<p align="center">
  <img src="docs/images/cleanup-review.png" width="620" alt="Quick Drop Zone cleanup review showing checked screenshot files assigned to Screenshots, the Downloads-only trash-suggestions note, and 8 selected with Approve &amp; Move available">
</p>

## Undo the latest move

A completed move can be reversed from the main window.

<p align="center">
  <img src="docs/images/undo-last-move.png" width="620" alt="Quick Drop Zone main window showing 24 moved items and the Undo Last Move control">
</p>

## Features

- Drop a file into the menu-bar popover, review the reason, then explicitly choose a destination. Uncertain files stay unsorted.
- Extension rules are followed exactly. Local learning suggests a destination only after at least three distinct same-extension examples share a meaningful subject. Screenshot detection checks local capture metadata.
- Cleanup reviews visible top-level files in Downloads or a folder you choose. New-folder groups start unchecked and are created only after approval.
- Trash suggestions are separate and unchecked. Only a `.dmg` directly in Downloads with its matching `.app` directly in `/Applications` can be moved to macOS Trash; files are never permanently deleted.
- Undo the latest move.
- No file contents are read, and Quick Drop Zone has no networking or analytics.

## Install

1. Download the ZIP from the latest release and unzip it.
2. Move **Quick Drop Zone.app** into **/Applications** before its first launch.
3. Open the app from **/Applications**.
4. Click the app’s tray-and-arrow icon in the menu bar. Choose folders through the app when adding favorites or reviewing files.

<details>
<summary>First launch: macOS security prompt</summary>

The release is ad-hoc signed and not notarized. If macOS blocks the app, go to **System Settings → Privacy &amp; Security → Open Anyway**, confirm, then reopen Quick Drop Zone from **/Applications**.

</details>

No Full Disk Access permission is needed; folder access is granted through the folders you choose in the app.

## Privacy

Preferences, learned filename patterns, names, and screenshot metadata stay on your Mac. The app does not read file contents or send files, filenames, or metadata to an online service. Uncertain suggestions are not sent to an AI service or used as a destination fallback.

<p align="center">
  <img src="docs/images/settings-privacy.png" width="900" alt="Quick Drop Zone Settings showing the Screenshots rule, minimum related files set to 4, and privacy notes that files, names, metadata, rules, and learning stay on this Mac; moves and folder creation require approval">
</p>

<details>
<summary>Build and test</summary>

Requires Xcode with the macOS 26 SDK.

```sh
swift test
bash Scripts/package-app.sh
bash Scripts/smoke-test.sh
```

</details>

<details>
<summary>Maintainer release checklist</summary>

1. Wait for the macOS CI run to pass.
2. Download its ZIP and SHA-256 sidecar, then verify the checksum and extracted app.
3. Attach those exact files to the versioned GitHub Release. Do not rebuild after verification.
4. Download the public ZIP and confirm it matches the CI checksum.

</details>

## License

MIT. See [LICENSE](LICENSE).
