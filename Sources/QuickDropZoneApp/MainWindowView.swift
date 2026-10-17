import AppKit
import QuickDropZoneCore
import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            SidebarView(selection: $model.selectedTab)
                .frame(width: 214)
            Rectangle()
                .fill(QDZStyle.hairline)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowBackground().ignoresSafeArea())
        .qdzChrome()
        .frame(minWidth: 840, minHeight: 580)
        .alert("Quick Drop Zone", isPresented: Binding(
            get: { model.userError != nil },
            set: { if !$0 { model.userError = nil } }
        )) {
            Button("OK", role: .cancel) { model.userError = nil }
        } message: {
            Text(model.userError ?? "")
        }
    }

    /// The five pages. There is no toolbar or inspector, so the window never changes shape between pages.
    @ViewBuilder
    private var detail: some View {
        switch model.selectedTab {
        case .activity: ActivityTab()
        case .cleanup: CleanUpTab()
        case .find: FindTab()
        case .folders: FoldersTab()
        case .settings: SettingsTab()
        }
    }
}

/// The list of pages on the left, with Apple Intelligence's state at the bottom.
struct SidebarView: View {
    @Binding var selection: MainTab

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandMark()
                .padding(.bottom, 20)
            ForEach(MainTab.allCases) { tab in
                SidebarRow(tab: tab, isSelected: selection == tab) {
                    selection = tab
                }
            }
            Spacer(minLength: 12)
            IntelligenceCard()
        }
        .padding(.horizontal, 14)
        .padding(.top, 46)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.2).ignoresSafeArea())
    }
}

/// The app icon and name at the top of the sidebar (under the window's traffic lights).
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Drop Zone")
                    .font(.system(size: 13, weight: .semibold))
                Text("FILE ORGANIZER")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(QDZStyle.brass.opacity(0.85))
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

struct SidebarRow: View {
    let tab: MainTab
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? QDZStyle.brass : Color.secondary)
                Text(tab.title)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(rowFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(QDZStyle.brass)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var rowFill: Color {
        if isSelected { return Color.white.opacity(0.1) }
        return hovering ? Color.white.opacity(0.05) : Color.clear
    }
}

/// Apple Intelligence's state, as a small card at the bottom of the sidebar.
struct IntelligenceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let available = model.aiUnavailableReason == nil
        VStack(spacing: 6) {
            Image(systemName: available ? "sparkles" : "sparkles.slash")
                .font(.title3)
                .foregroundStyle(available ? QDZStyle.brass : Color.secondary)
            Text("Apple Intelligence")
                .font(.callout.weight(.medium))
            Text(model.aiUnavailableReason ?? "On, running on this Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: 14)
    }
}

// MARK: - Activity

struct ActivityTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page(title: "Activity", subtitle: "Everything Quick Drop Zone moved, renamed or suggested. Anything it did can be undone.") {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label(watchSummary, systemImage: model.isWatching ? "eye" : "eye.slash")
                    IntelligenceStatus()
                    if let status = model.statusMessage {
                        Caption(status)
                    }
                }
            }
            let waiting = model.openSuggestions
            if !waiting.isEmpty {
                GroupBox("Waiting for you") {
                    VStack(alignment: .leading, spacing: 8) {
                        Caption("New files Quick Drop Zone wasn't sure about. Nothing moves until you click.")
                        ForEach(waiting) { entry in
                            ActivityRow(entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            let recent = model.activity.filter { $0.kind != .suggested }
            if recent.isEmpty {
                Caption("Nothing yet. Drop a file on the menu-bar icon or panel, or save one to a watched folder.")
            } else {
                let sections = ActivityGrouping.sections(recent)
                ForEach(0..<sections.count, id: \.self) { index in
                    daySection(sections[index], showsActions: index == 0)
                }
            }
        }
    }

    private func daySection(_ section: ActivityDaySection, showsActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.title).font(.headline)
                Spacer()
                if showsActions {
                    if model.lastMove != nil {
                        Button("Undo Last Move", systemImage: "arrow.uturn.backward") { model.undoLastMove() }
                    }
                    Button("Clear List") { model.clearActivity() }
                }
            }
            .buttonStyle(.pill)
            ForEach(section.entries) { entry in
                ActivityRow(entry: entry)
            }
        }
    }

    private var watchSummary: String {
        var places: [String] = []
        if model.watchDownloads { places.append("Downloads") }
        if model.watchDesktop { places.append("Desktop") }
        places += model.watchedFolders.map(\.name)
        guard !places.isEmpty else { return "Not watching any folders. Turn watching on in Settings." }
        let list = places.count == 1 ? places[0] : places.dropLast().joined(separator: ", ") + " and " + (places.last ?? "")
        return "Watching \(list) for new files."
    }
}

// MARK: - Clean up

struct CleanUpTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmMove = false
    @State private var confirmTrash = false

    var body: some View {
        Page(title: "Clean Up", subtitle: "Review a folder's loose files. Nothing moves, gets renamed or goes to Trash until you approve it.") {
            HStack(spacing: 10) {
                Button("Clean Downloads", systemImage: "arrow.down.circle") { model.startDownloadsCleanup() }
                Button("Choose Folder…", systemImage: "folder") { model.chooseCleanupFolder() }
                Spacer()
                if model.cleanupFolder != nil, model.aiReady, model.cleanupProgress == nil {
                    Button("Ask Apple Intelligence Again", systemImage: "sparkles") {
                        Task { await model.reviewCleanupWithAI() }
                    }
                }
            }
            if let progress = model.cleanupProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Caption(progress)
                }
            }
            if model.aiReady, !model.hasDescribedFolders, !model.favoriteFolders.isEmpty {
                Caption("Apple Intelligence won't suggest any of your folders until you add a note saying what goes in one (Folders & Rules). It still offers clearer names.")
            }
            if model.cleanupFolder == nil {
                ContentUnavailableView("Choose a folder to clean up", systemImage: "sparkles.rectangle.stack",
                                       description: Text("Start with Downloads, or pick any folder."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                filesSection
                groupsSection
                trashSection
                approveBar
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        GroupBox("Files in \(model.cleanupTitle) (\(model.cleanupRows.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if model.cleanupRows.isEmpty {
                    Caption("No loose files to review here.")
                } else {
                    Caption("Checked files move to the folder shown. Renames are offered by Apple Intelligence and stay unchecked until you tick them.")
                    ForEach(model.cleanupRows) { row in
                        CleanupRowView(row: row)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var groupsSection: some View {
        if !model.folderGroups.isEmpty {
            GroupBox("Suggested new folders") {
                VStack(alignment: .leading, spacing: 10) {
                    Caption("Files that belong together. Groups start unchecked; a folder is created inside \(model.cleanupTitle) only after you approve it. You can edit the name.")
                    ForEach(model.folderGroups) { group in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("Include group", isOn: Binding(
                                get: { model.selectedGroupIDs.contains(group.id) },
                                set: { model.setFolderGroupSelected(id: group.id, selected: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 3) {
                                TextField("Folder name", text: Binding(
                                    get: { group.name },
                                    set: { model.renameFolderGroup(id: group.id, to: $0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                                Caption(group.reason)
                                Text(group.files.prefix(4).map(\.lastPathComponent).joined(separator: ", ") + (group.files.count > 4 ? "…" : ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var trashSection: some View {
        if !model.trashRows.isEmpty {
            GroupBox("Installers you can move to Trash") {
                VStack(alignment: .leading, spacing: 8) {
                    Caption("Only .dmg files in Downloads whose app is already installed in Applications. Always unchecked; Trash can be emptied only by you.")
                    ForEach(model.trashRows) { row in
                        Toggle(isOn: Binding(
                            get: { row.isSelected },
                            set: { model.setTrashSelected(entryID: row.id, selected: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.url.lastPathComponent)
                                Caption(row.reason)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    Button("Move Selected to Trash (\(model.selectedTrashCount))", systemImage: "trash") { confirmTrash = true }
                        .disabled(model.selectedTrashCount == 0)
                        .confirmationDialog("Move the selected installers to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
                            Button("Move to Trash", role: .destructive) { model.moveSelectedInstallersToTrash() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You can restore them from Trash.")
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private var approveBar: some View {
        HStack {
            Caption("\(model.selectedMoveCount) to move · \(model.selectedRenameCount) to rename")
            Spacer()
            if model.lastMove != nil {
                Button("Undo Last Move", systemImage: "arrow.uturn.backward") { model.undoLastMove() }
            }
            Button("Approve", systemImage: "checkmark.circle.fill") { confirmMove = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedMoveCount == 0 && model.selectedRenameCount == 0)
                .confirmationDialog("Apply the selected moves and renames?", isPresented: $confirmMove, titleVisibility: .visible) {
                    Button("Apply") { model.moveSelectedCleanupItems() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Undo Last Move reverses all of it. Nothing is deleted.")
                }
        }
    }
}

struct CleanupRowView: View {
    @Environment(AppModel.self) private var model
    let row: CleanupEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Move", isOn: Binding(
                get: { row.isSelected },
                set: { model.setCleanupSelected(entryID: row.id, selected: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(row.destinationID == nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.url.lastPathComponent)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Caption(row.suggestionReason ?? "No suggestion. Choose a folder.")
                if let summary = row.summary {
                    Caption(summary)
                }
                if let proposed = row.proposedName {
                    Toggle("Rename to “\(proposed)”", isOn: Binding(
                        get: { row.renameSelected },
                        set: { model.setRenameSelected(entryID: row.id, selected: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
            Spacer(minLength: 6)
            Picker("Folder", selection: Binding(
                get: { row.destinationID ?? "" },
                set: { model.setCleanupDestination(entryID: row.id, destinationID: $0) }
            )) {
                Text("Choose…").tag("")
                ForEach(model.favoriteFolders) { folder in Text(folder.name).tag(folder.id) }
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(8)
        .cardSurface(radius: 10)
    }
}

// MARK: - Find

struct FindTab: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        Page(title: "Find", subtitle: "Describe a file in your own words, like “the PDF from the dentist last month” or “screenshots of the EchoLedger report”.") {
            HStack(spacing: 10) {
                TextField("Describe the file…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.search(text) }
                Button("Find", systemImage: "magnifyingglass") { model.search(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || model.isSearching)
            }
            if model.isSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Caption("Searching this Mac…")
                }
            }
            if let note = model.searchNote {
                Caption(note)
            }
            Caption(model.aiReady ? "Apple Intelligence turns your words into a search of your home folder, using the same index as Finder."
                    : "Searching names and text for your words. Turn on Apple Intelligence for dates, file types and websites.")
            ForEach(model.searchResults) { result in
                SearchResultRow(result: result)
            }
        }
    }
}

struct SearchResultRow: View {
    @Environment(AppModel.self) private var model
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: result.url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Button("Open") { NSWorkspace.shared.open(result.url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
                Button("What Is This?") { model.explain(result.url) }
                    .disabled(!model.aiReady || model.explaining.contains(result.id))
            }
            .controlSize(.small)
            if model.explaining.contains(result.id) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Caption("Apple Intelligence is reading it…")
                }
                .padding(.leading, 38)
            } else if let explanation = model.explanations[result.id] {
                Caption(explanation)
                    .padding(.leading, 38)
            }
        }
        .padding(8)
        .cardSurface(radius: 10)
    }

    private var detail: String {
        let folder = result.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        guard let modified = result.modified else { return folder }
        return "\(folder) · \(modified.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Folders and rules

struct FoldersTab: View {
    @Environment(AppModel.self) private var model
    @State private var editorRule: RuleDraft?

    var body: some View {
        Page(title: "Folders & Rules", subtitle: "Where files can go, and rules that always win. Apple Intelligence only suggests folders you describe.") {
            GroupBox("Favorite folders") {
                VStack(alignment: .leading, spacing: 10) {
                    if model.favoriteFolders.isEmpty {
                        Caption("No favorites yet. Add the folders you save files to.")
                    } else {
                        Caption("Every favorite is a place to drop files. Apple Intelligence only suggests a folder that has a note saying what goes there, and only for files that plainly match it. Leave the note empty to keep a folder for drag and drop, your rules and your own moves.")
                    }
                    ForEach(model.favoriteFolders) { folder in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(QDZStyle.brass)
                                Text(folder.name)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Button("Remove", role: .destructive) { model.removeFavorite(id: folder.id) }
                                    .buttonStyle(.borderless)
                            }
                            TextField("What goes here? (optional, e.g. Chase statement CSV exports only)", text: Binding(
                                get: { folder.purpose ?? "" },
                                set: { model.setFolderPurpose(id: folder.id, to: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .padding(.leading, 26)
                            Caption(folder.purpose?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                    ? "Apple Intelligence may suggest this folder for files that match the note."
                                    : "Drag and drop, rules and your own moves only.")
                                .padding(.leading, 26)
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Add Favorite Folder…", systemImage: "folder.badge.plus") { model.addFavoriteFromPanel() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Rules") {
                VStack(alignment: .leading, spacing: 8) {
                    Caption("A rule matches file types, words in the name, or both, and always wins. A folder used by a rule only gets files that match one of its rules.")
                    ForEach(model.rules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                Caption(ruleSummary(rule))
                            }
                            Spacer()
                            Button("Edit") { editorRule = RuleDraft(rule: rule) }
                            Button(role: .destructive) { model.removeRule(id: rule.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove rule \(rule.name)")
                        }
                    }
                    Button("Add Rule…", systemImage: "plus") { editorRule = RuleDraft(rule: nil) }
                        .disabled(model.favoriteFolders.isEmpty)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $editorRule) { draft in
            RuleEditorView(rule: draft.rule)
                .environment(model)
        }
    }

    private func ruleSummary(_ rule: DestinationRule) -> String {
        let types = rule.extensions.sorted().map { ".\($0)" }.joined(separator: ", ")
        let words = rule.keywords.joined(separator: ", ")
        let match = [types, words].filter { !$0.isEmpty }.joined(separator: " · ")
        return "\(match) → \(model.destinationName(for: rule.destinationID) ?? "Missing folder")"
    }
}

struct RuleDraft: Identifiable {
    let id = UUID()
    let rule: DestinationRule?
}

struct RuleEditorView: View {
    @Environment(AppModel.self) private var model
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
            Text(originalRule == nil ? "Add Rule" : "Edit Rule")
                .font(.title2.weight(.semibold))
            TextField("Rule name", text: $name)
            TextField("File types (e.g. pdf, docx)", text: $extensionsText)
            TextField("Words in the file name (e.g. bill, invoice)", text: $keywordsText)
            Picker("Folder", selection: $destinationID) {
                Text("Choose…").tag("")
                ForEach(model.favoriteFolders) { folder in Text(folder.name).tag(folder.id) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save Rule") {
                    let extensions = Set(extensionsText.split(separator: ",").map {
                        String($0).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                    }.filter { !$0.isEmpty })
                    let keywords = keywordsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    model.saveRule(id: originalRule?.id, name: name, extensions: extensions, keywords: keywords, destinationID: destinationID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isIncomplete)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if destinationID.isEmpty { destinationID = model.favoriteFolders.first?.id ?? "" }
        }
    }

    private var isIncomplete: Bool {
        destinationID.isEmpty || (extensionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && keywordsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page(title: "Settings", subtitle: "How much Quick Drop Zone does on its own, and what it watches.") {
            GroupBox("Apple Intelligence") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingToggle("Use Apple Intelligence on this Mac", isOn: $model.aiEnabled)
                    SettingToggle("Look inside files (PDF and document text, text and objects in images)", isOn: $model.readContents)
                        .disabled(!model.aiEnabled)
                    IntelligenceStatus()
                    Caption("Only Apple's on-device model is used, never a cloud service. Long numbers such as account and card numbers are hidden from it. Everything still works with this off.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Moving files") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingToggle("Move files it's sure about by itself (with Undo)", isOn: $model.autoMove)
                    Caption("Sure means: one of your rules, a macOS screenshot, a pattern from 3+ of your own moves, or Apple Intelligence certain about a folder you described and backed by what's inside the file or where it came from. Renames and new folders always wait for you.")
                    SettingToggle("Show a notification for each automatic move or suggestion", isOn: $model.notificationsEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Watch for new files") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingToggle("Downloads", isOn: $model.watchDownloads)
                    SettingToggle("Desktop (where screenshots go)", isOn: $model.watchDesktop)
                    ForEach(model.watchedFolders) { folder in
                        HStack {
                            Image(systemName: "eye").foregroundStyle(QDZStyle.brass)
                            Text(folder.name)
                            Spacer()
                            Button("Stop Watching") { model.removeWatchedFolder(id: folder.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Watch Another Folder…", systemImage: "plus") { model.addWatchedFolder() }
                    Caption("Only files that arrive after watching starts are handled, once they've finished downloading. Files already there are never touched. Partial downloads and installers are left alone.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("New folder suggestions") {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: Binding(
                        get: { model.minimumRelatedFileCount },
                        set: { model.setMinimumRelatedFileCount($0) }
                    ), in: FolderGroupingSettings.minimumAllowed...FolderGroupingSettings.maximumAllowed) {
                        Text("Minimum related files: \(model.minimumRelatedFileCount)")
                    }
                    Caption("A new folder is only suggested when at least this many files share a specific name (like a client or trip), never a broad word like school or finance. Default: 4.")
                    SettingToggle("Let Apple Intelligence suggest new folders for related files", isOn: $model.aiGroupsEnabled)
                        .disabled(!model.aiEnabled)
                    Caption("Off by default. When on, only for one specific project, trip, class or event with at least \(model.aiGroupMinimum) files. Suggestions always start unchecked.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            GroupBox("Privacy and safety") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Files, names, contents, rules and learning stay on this Mac. Quick Drop Zone has no networking and no analytics.", systemImage: "lock.shield")
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Nothing is ever permanently deleted. Every move and rename can be undone from Activity or Undo Last Move.", systemImage: "arrow.uturn.backward.circle")
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Only .dmg installers whose app is already installed can be moved to Trash, after you confirm.", systemImage: "hand.raised")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }
}
