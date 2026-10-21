<p align="center">
  <img src="docs/images/levant-icon.png" width="88" alt="Levant app icon">
</p>

<h1 align="center">Levant</h1>

<p align="center">Files that sort themselves. A menu-bar file organizer with Apple Intelligence, running entirely on your Mac.</p>

<p align="center"><a href="https://github.com/echoappstudio/Levant/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+ · Apple Silicon</p>

<p align="center">
  <a href="https://github.com/echoappstudio/Levant/releases/latest"><img src="https://img.shields.io/github/v/release/echoappstudio/Levant?display_name=tag" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 or later">
  <a href="https://github.com/echoappstudio/Levant/actions/workflows/macos-ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/echoappstudio/Levant/macos-ci.yml?branch=main&amp;label=macOS%20CI" alt="macOS CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Features

- **Drop files on the menu-bar icon or its panel.** The panel stays open until you close it, so you can pick files up in Finder without it disappearing.
- **Files it's sure about are filed right away**, with Undo: your rules, macOS screenshots, patterns learned from your own moves, and Apple Intelligence when it's certain and backed by what's inside the file. Everything else waits for one click.
- **Apple Intelligence understands your files** on this Mac: text in PDFs and documents, text and objects in screenshots and photos, and the website a download came from.
- **You decide which folders it may use.** Give a favorite folder a short note saying what goes there (“Chase statement CSV exports only”), and Apple Intelligence suggests it only for files that plainly match. Folders without a note stay yours: drag and drop, rules and your own moves only.
- **Watches Downloads, Desktop and folders you choose.** New files are handled once they've finished downloading, with a notification to Undo or Move. Files that were already there are never touched.
- **Clearer names.** `document (3).pdf` can become `2026-10 Lease renewal.pdf`; renames always wait for your approval.
- **Clean up any folder.** Review suggestions for loose files, approve new folders for files about one specific thing (a client, a trip, a class project), and move installers of apps you already have to Trash. Apple Intelligence's new-folder ideas are off until you turn them on.
- **Find files in plain words**, like “the PDF from the dentist last month”, using the same index as Finder search.
- **What is this file?** A one-line summary of any file.
- **Activity** lists everything that moved, was renamed or is waiting for you, grouped by day. Everything can be undone; nothing is ever permanently deleted.
- **A refined, watch-dial look with eight skins** (Slate and Oyster by default, following your Mac's light and dark setting, or one skin of your choice; the app icon in the Dock and Finder follows the skin), and a sidebar for Activity, Clean Up, Find, Folders & Rules and Settings.

## Install

1. Download the ZIP from the latest release and unzip it.
2. Move **Levant.app** into **/Applications**, then open it. It is signed and notarized by Apple.
3. Levant updates itself: it checks for a new version when it starts and every hour, and installs it once no file is waiting to be filed. **Check for Updates…** is in the panel's menu, and **Settings → Updates** has the options.
4. Allow access to Downloads and Desktop when macOS asks (for watching), and allow notifications if you want Undo and Move buttons on them.
5. For the Apple Intelligence features, turn on **System Settings → Apple Intelligence & Siri**. Everything else works without it.

**Coming from Quick Drop Zone?** Levant is the same app under a new name (2.6.0). The first time it opens it asks Quick Drop Zone to quit, then brings over your favorite folders, notes, rules, learned patterns, activity and settings. Nothing is deleted from the old app, so once Levant looks right you can delete Quick Drop Zone. macOS treats Levant as a new app, so allow access to Downloads and Desktop and allow notifications again. To let Apple Intelligence suggest a folder, add a note to it in **Folders & Rules**.

## How it decides

1. **Your rules** always win. A folder used by a rule only receives files that match one of its rules.
2. **macOS screenshots** go to a folder named Screenshots.
3. **Patterns you taught it**: after three or more of your own moves share a subject, similar files follow.
4. **Apple Intelligence** looks at the file and picks one of the folders you described, or none. Its answer is checked: it can only choose a favorite folder that has a note, never one reserved by a rule, and only when it's sure. Guesses are dropped. It moves a file by itself only when the file's contents or download source back it up; otherwise it suggests.

Partial downloads, hidden files and installers are never moved automatically.

## Privacy

Everything happens on your Mac. Levant has no analytics. The only thing it sends online is the check for a new version of itself, with GitHub. Files, names and contents are never uploaded. Apple Intelligence runs with Apple's on-device model only, never a cloud service, and long numbers such as account and card numbers are hidden from it. Reading inside files can be turned off in Settings, and so can Apple Intelligence; the app keeps working either way.

<details>
<summary>Build and test</summary>

Requires Xcode with the macOS 26 SDK.

```sh
swift test
bash Scripts/package-app.sh
bash Scripts/smoke-test.sh
```

</details>

## License

MIT. See [LICENSE](LICENSE).
