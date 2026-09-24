# Decisions

## Native macOS and local-only behavior

- Use Swift and SwiftUI, with AppKit for menu-bar integration and other native APIs. Target macOS 26 and newer; the app stays out of the Dock.
- Runtime file handling, preferences, learning, and any metadata inspection stay on the Mac. No cloud processing, analytics, or upload of files, names, or contents. GitHub is used only for authorized source, CI, and app releases—not personal files.

## Approval and file safety

- Suggestions never perform actions. Moving files, creating folders, and moving an eligible installer to Trash require the user's explicit approval.
- Never permanently delete files or empty Trash. Trash suggestions are a separate, unchecked review list, restricted to `.dmg` installers in Downloads whose matching `.app` is installed directly in `/Applications`.
- Undo restores moved files. It removes a newly created folder only when the app created it and that folder is empty.

## Suggestions and grouping

- Enforce a user's rule exactly, especially file-type conditions; a rule-constrained folder does not receive unrelated fallback suggestions.
- Prefer specific evidence over broad similarity. Screenshot identification uses macOS screen-capture metadata, with a `Screenshot… .png` filename as backup. Include a short reason for each suggestion; show no destination when confidence is weak.
- Learning needs repeated, distinct examples with a meaningful shared subject. AI cannot override rules or send data off-device; if confidence cannot be enforced, omit the AI guess.
- Suggest new folders only for files with a specific shared subject or project, with a configurable minimum of four related files by default—not generic file types or dates alone. Let the user edit the name and approve before creating the folder.

## Build and distribution

- Use a standard macOS GitHub Actions runner to run tests, build the native `.app`, validate the exact extracted ZIP, and smoke-launch it. CI output is the source artifact for releases.
- Attach the tested ZIP and checksum sidecar to a versioned GitHub Release, then verify the public download against the CI checksum. An Actions artifact or successful compile alone is not the final user handoff.
