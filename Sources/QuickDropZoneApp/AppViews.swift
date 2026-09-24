import AppKit
import QuickDropZoneCore
import SwiftUI
import UniformTypeIdentifiers

struct MainPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var showingCleanup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Quick Drop Zone")
                    .font(.headline)
                Spacer()
                Button("Settings") { openSettings() }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open Quick Drop Zone settings")
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider()
            if showingCleanup {
                CleanupView(onBack: { showingCleanup = false })
            } else {
                DropZoneView(onCleanup: {
                    model.startDownloadsCleanup()
                    showingCleanup = true
                })
            }
        }
        .frame(width: 420, height: 590)
        .background(.background)
        .alert("Quick Drop Zone", isPresented: Binding(
            get: { model.userError != nil },
            set: { if !$0 { model.userError = nil } }
        )) {
            Button("OK", role: .cancel) { model.userError = nil }
        } message: {
            Text(model.userError ?? "")
        }
    }
}

private struct DropZoneView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    let onCleanup: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 28))
                            Text("Drop a file here")
                                .font(.headline)
                            Text("Nothing moves until you choose a destination.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .frame(height: 122)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                    .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: receiveDrop)
                    .accessibilityLabel("Drop a file to choose where it goes")

                if let url = model.pendingURL {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(url.lastPathComponent, systemImage: "doc")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 6)
                            Button { model.cancelPendingDrop() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel pending file")
                        }
                        if let reason = model.pendingSuggestionReason, let name = model.destinationName(for: model.pendingSuggestionID) {
                            Label("Suggested: \(name) — \(reason)", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Choose a favorite folder. No confident match was found, so no destination is preselected.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if model.favoriteFolders.isEmpty {
                            Text("Add a favorite folder in Settings first.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            ForEach(model.favoriteFolders) { folder in
                                Button {
                                    model.movePending(to: folder.id)
                                } label: {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text("Move to \(folder.name)")
                                        Spacer()
                                        if folder.id == model.pendingSuggestionID {
                                            Text("Suggested")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }

                if let status = model.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if model.lastMove != nil {
                        Button("Undo Last Move", systemImage: "arrow.uturn.backward") { model.undoLastMove() }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Clean up…", systemImage: "sparkles.rectangle.stack", action: onCleanup)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
        }
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let value = item as? String {
                    url = URL(string: value)
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor in model.receiveDrop(url) }
            }
        }
        return true
    }
}

private struct CleanupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmMove = false
    @State private var confirmTrash = false
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.borderless)
                Spacer()
                Text(model.cleanupTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Menu {
                    Button("Clean Downloads", systemImage: "arrow.down.circle") { model.startDownloadsCleanup() }
                    Button("Choose Folder…", systemImage: "folder") { model.chooseCleanupFolder() }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Choose cleanup folder")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Review every choice. Only the buttons below perform moves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !model.cleanupRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Files to organize (\(model.cleanupRows.count))")
                                .font(.headline)
                            ForEach(model.cleanupRows) { row in
                                cleanupRow(row)
                            }
                        }
                    } else if model.trashRows.isEmpty {
                        ContentUnavailableView("No files found", systemImage: "checkmark.circle", description: Text("This folder has no visible top-level files to review."))
                            .padding(.vertical, 14)
                    }

                    if !model.folderGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested new folders")
                                .font(.headline)
                            Text("Groups start unchecked. They appear only when filenames share a specific subject. A folder is created only after approval, inside the folder being cleaned.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(model.folderGroups) { group in
                                HStack(alignment: .top, spacing: 8) {
                                    Toggle("Include group", isOn: Binding(
                                        get: { model.selectedGroupIDs.contains(group.id) },
                                        set: { model.setFolderGroupSelected(id: group.id, selected: $0) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    VStack(alignment: .leading, spacing: 2) {
                                        TextField("Proposed folder name", text: Binding(
                                            get: { group.name },
                                            set: { model.renameFolderGroup(id: group.id, to: $0) }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        Text(group.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("Create in: \(model.cleanupFolder?.path ?? "the folder being cleaned")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                        Text(group.files.prefix(2).map(\.lastPathComponent).joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Trash suggestions — Downloads only", systemImage: "trash")
                            .font(.headline)
                        Text("Only .dmg files matching apps already installed directly in /Applications can appear here. They are always unchecked. Moving to Trash is reversible; nothing is permanently deleted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if model.trashRows.isEmpty {
                            Text("No eligible installers found.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.trashRows) { row in
                                Toggle(isOn: Binding(
                                    get: { row.isSelected },
                                    set: { model.setTrashSelected(entryID: row.id, selected: $0) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.url.lastPathComponent)
                                            .lineLimit(1)
                                        Text(row.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                            Button("Move selected to Trash (\(model.selectedTrashCount))", systemImage: "trash") {
                                confirmTrash = true
                            }
                            .disabled(model.selectedTrashCount == 0)
                            .buttonStyle(.bordered)
                            .confirmationDialog("Move the selected installer images to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
                                Button("Move to Trash", role: .destructive) { model.moveSelectedInstallersToTrash() }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("These are the only files Quick Drop Zone may suggest moving to Trash. You can restore them from Trash.")
                            }
                        }
                    }
                    .padding(12)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    if let status = model.statusMessage {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }

            Divider()
            HStack {
                Text("\(model.selectedMoveCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Approve & Move", systemImage: "arrow.right.circle.fill") {
                    confirmMove = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedMoveCount == 0)
                .confirmationDialog("Move the selected files?", isPresented: $confirmMove, titleVisibility: .visible) {
                    Button("Move Selected Files") { model.moveSelectedCleanupItems() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Selected files will move to the displayed destinations. Selected groups will create the edited folder inside the folder being cleaned. No files are permanently deleted.")
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func cleanupRow(_ row: CleanupEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { row.isSelected },
                set: { model.setCleanupSelected(entryID: row.id, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.url.lastPathComponent)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.suggestionReason ?? "No suggestion — choose a folder manually.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Picker("Destination", selection: Binding(
                get: { row.destinationID ?? "" },
                set: { model.setCleanupDestination(entryID: row.id, destinationID: $0) }
            )) {
                Text("Choose…").tag("")
                ForEach(model.favoriteFolders) { folder in Text(folder.name).tag(folder.id) }
            }
            .labelsHidden()
            .frame(width: 125)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingRuleEditor = false
    @State private var ruleDraft: DestinationRule?

    var body: some View {
        Form {
            Section("Favorite folders") {
                if model.favoriteFolders.isEmpty {
                    Text("No favorites yet. Add folders such as Bills, Taxes, Photos, or Work.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.favoriteFolders) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        Text(folder.name)
                        Spacer()
                        Button("Remove", role: .destructive) { model.removeFavorite(id: folder.id) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Favorite Folder…", systemImage: "folder.badge.plus") { model.addFavoriteFromPanel() }
            }

            Section("Suggestion rules") {
                Text("A rule can match a file extension, one or more filename keywords, or both. Explicit rules take priority over learning and built-in suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.rules.isEmpty {
                    Text("No custom rules yet. Suggestions require a specific filename match, screenshot metadata, or a repeated learned pattern; file type alone is not enough.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.rules) { rule in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                            Text("\(rule.extensions.sorted().map { ".\($0)" }.joined(separator: ", "))  \(rule.keywords.joined(separator: ", ")) → \(model.destinationName(for: rule.destinationID) ?? "Missing folder")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") {
                            ruleDraft = rule
                            showingRuleEditor = true
                        }
                        Button(role: .destructive) { model.removeRule(id: rule.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove rule \(rule.name)")
                    }
                }
                Button("Add Rule…", systemImage: "plus") {
                    ruleDraft = nil
                    showingRuleEditor = true
                }
                .disabled(model.favoriteFolders.isEmpty)
            }

            Section("New folder suggestions") {
                Stepper(
                    value: Binding(
                        get: { model.minimumRelatedFileCount },
                        set: { model.setMinimumRelatedFileCount($0) }
                    ),
                    in: FolderGroupingSettings.minimumAllowed...FolderGroupingSettings.maximumAllowed
                ) {
                    Text("Minimum related files: \(model.minimumRelatedFileCount)")
                }
                Text("Only propose a new folder when at least this many files share a specific subject or project. Default: 4.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Privacy and safety") {
                Label("Files, filenames, screenshot metadata, rules, and learning stay on this Mac. No AI service or file data is sent online; uncertain files get no suggested destination.", systemImage: "lock.shield")
                    .fixedSize(horizontal: false, vertical: true)
                Label("Moves and folder creation happen only after you approve them. Trash suggestions are limited to matching installed-app .dmg files in Downloads, and are unchecked by default.", systemImage: "hand.raised")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 540)
        .navigationTitle("Quick Drop Zone Settings")
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorView(rule: ruleDraft)
                .environmentObject(model)
        }
    }
}

private struct RuleEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let originalRule: DestinationRule?
    @State private var name: String
    @State private var extensionsText: String
    @State private var keywordsText: String
    @State private var destinationID: String

    init(rule: DestinationRule?) {
        originalRule = rule
        _name = State(initialValue: rule?.name ?? "")
        _extensionsText = State(initialValue: rule?.extensions.sorted().joined(separator: ", ") ?? "")
        _keywordsText = State(initialValue: rule?.keywords.joined(separator: ", ") ?? "")
        _destinationID = State(initialValue: rule?.destinationID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(originalRule == nil ? "Add Suggestion Rule" : "Edit Suggestion Rule")
                .font(.title2.weight(.semibold))
            TextField("Rule name", text: $name)
            TextField("File extensions (e.g. pdf, docx)", text: $extensionsText)
            TextField("Filename keywords (e.g. bill, invoice)", text: $keywordsText)
            Picker("Destination", selection: $destinationID) {
                Text("Choose…").tag("")
                ForEach(model.favoriteFolders) { folder in Text(folder.name).tag(folder.id) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save Rule") {
                    let extensions = Set(extensionsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }.filter { !$0.isEmpty })
                    let keywords = keywordsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    model.saveRule(id: originalRule?.id, name: name, extensions: extensions, keywords: keywords, destinationID: destinationID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationID.isEmpty || (extensionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && keywordsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if destinationID.isEmpty { destinationID = model.favoriteFolders.first?.id ?? "" }
        }
    }
}
