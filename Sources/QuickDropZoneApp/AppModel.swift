import AppKit
import Combine
import Foundation
import QuickDropZoneCore
import UniformTypeIdentifiers

struct FavoriteFolder: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var bookmarkData: Data
}

struct CleanupEntry: Identifiable {
    var id: String { url.path }
    let url: URL
    var destinationID: String?
    var suggestionReason: String?
    var isSelected: Bool
}

struct TrashEntry: Identifiable {
    var id: String { url.path }
    let url: URL
    let reason: String
    var isSelected: Bool
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var favoriteFolders: [FavoriteFolder] = []
    @Published private(set) var rules: [DestinationRule] = []
    @Published private(set) var learning: [LearningRecord] = []
    @Published var pendingURL: URL?
    @Published var pendingSuggestionID: String?
    @Published var pendingSuggestionReason: String?
    @Published var lastMove: MoveBatchReceipt?
    @Published var statusMessage: String?
    @Published var userError: String?

    @Published private(set) var cleanupFolder: URL?
    @Published private(set) var cleanupRows: [CleanupEntry] = []
    @Published private(set) var trashRows: [TrashEntry] = []
    @Published private(set) var folderGroups: [FolderGroup] = []
    @Published var selectedGroupIDs: Set<String> = []
    @Published private(set) var minimumRelatedFileCount: Int = FolderGroupingSettings.defaultMinimumRelatedFiles

    private let defaults: UserDefaults
    private let folderGroupingSettings: FolderGroupingSettings
    private let fileManager = FileManager.default
    private let mover = FileMoveService()
    private let foldersKey = "QuickDropZone.favoriteFolders.v1"
    private let rulesKey = "QuickDropZone.destinationRules.v1"
    private let learningKey = "QuickDropZone.learning.v1"
    private let lastMoveKey = "QuickDropZone.lastMove.v1"
    private var cleanupScopeURL: URL?
    private var cleanupScopeIsActive = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let groupingSettings = FolderGroupingSettings(defaults: defaults)
        folderGroupingSettings = groupingSettings
        minimumRelatedFileCount = groupingSettings.minimumRelatedFiles
        favoriteFolders = Self.decode([FavoriteFolder].self, key: foldersKey, defaults: defaults) ?? []
        rules = Self.decode([DestinationRule].self, key: rulesKey, defaults: defaults) ?? []
        learning = Self.decode([LearningRecord].self, key: learningKey, defaults: defaults) ?? []
        lastMove = Self.decode(MoveBatchReceipt.self, key: lastMoveKey, defaults: defaults)
            ?? Self.decode(FileMoveReceipt.self, key: lastMoveKey, defaults: defaults).map { MoveBatchReceipt(moves: [$0]) }
    }

    var destinations: [Destination] {
        favoriteFolders.map { Destination(id: $0.id, name: $0.name) }
    }

    var cleanupTitle: String {
        cleanupFolder?.lastPathComponent ?? "Choose a folder"
    }

    var selectedMoveCount: Int {
        cleanupRows.filter { $0.isSelected && $0.destinationID != nil }.count
            + folderGroups.filter { selectedGroupIDs.contains($0.id) && validFolderName($0.name) != nil }.reduce(0) { $0 + $1.files.count }
    }

    var selectedTrashCount: Int {
        trashRows.filter(\.isSelected).count
    }

    func addFavoriteFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add a favorite folder"
        panel.prompt = "Add Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let savedFolders = favoriteFolders
            let isDuplicate = savedFolders.contains { saved in
                var stale = false
                guard let existingURL = try? URL(resolvingBookmarkData: saved.bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return false }
                return existingURL.standardizedFileURL == url.standardizedFileURL
            }
            if isDuplicate {
                statusMessage = "That folder is already a favorite."
                return
            }
            favoriteFolders.append(FavoriteFolder(id: UUID().uuidString, name: url.lastPathComponent, bookmarkData: bookmark))
            persist(favoriteFolders, key: foldersKey)
            statusMessage = "Added \(url.lastPathComponent)."
        } catch {
            userError = "Could not save that folder bookmark: \(error.localizedDescription)"
        }
    }

    func removeFavorite(id: String) {
        favoriteFolders.removeAll { $0.id == id }
        rules.removeAll { $0.destinationID == id }
        learning.removeAll { $0.destinationID == id }
        persist(favoriteFolders, key: foldersKey)
        persist(rules, key: rulesKey)
        persist(learning, key: learningKey)
    }

    func saveRule(id: UUID?, name: String, extensions: Set<String>, keywords: [String], destinationID: String) {
        guard favoriteFolders.contains(where: { $0.id == destinationID }) else { return }
        let rule = DestinationRule(
            id: id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom rule" : name,
            extensions: extensions,
            keywords: keywords,
            destinationID: destinationID
        )
        if let existingIndex = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[existingIndex] = rule
        } else {
            rules.append(rule)
        }
        persist(rules, key: rulesKey)
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        persist(rules, key: rulesKey)
    }

    func destinationName(for id: String?) -> String? {
        guard let id else { return nil }
        return favoriteFolders.first(where: { $0.id == id })?.name
    }

    func receiveDrop(_ url: URL) {
        guard url.isFileURL else { return }
        pendingURL = url
        pendingSuggestionID = nil
        pendingSuggestionReason = nil
        statusMessage = nil

        let localSuggestion = SuggestionEngine.suggest(
            fileName: url.lastPathComponent,
            destinations: destinations,
            rules: rules,
            learning: learning,
            isScreenCapture: ScreenshotMetadata.isScreenCapture(at: url)
        )
        if let localSuggestion {
            pendingSuggestionID = localSuggestion.destinationID
            pendingSuggestionReason = localSuggestion.reason
        } else {
            statusMessage = "No confident match — choose a folder manually."
        }
    }

    func cancelPendingDrop() {
        pendingURL = nil
        pendingSuggestionID = nil
        pendingSuggestionReason = nil
    }

    func movePending(to destinationID: String) {
        guard let source = pendingURL, let destination = resolvedURL(for: destinationID) else {
            userError = "Choose a favorite folder before moving this file."
            return
        }
        do {
            let receipt = try move(source, into: destination)
            saveLastMove(MoveBatchReceipt(moves: [receipt]))
            remember(file: source, destinationID: destinationID)
            statusMessage = "Moved to \(destinationName(for: destinationID) ?? destination.lastPathComponent)."
            cancelPendingDrop()
        } catch {
            userError = "Could not move the file: \(error.localizedDescription)"
        }
    }

    func undoLastMove() {
        guard let receipt = lastMove else { return }
        do {
            try mover.undo(receipt)
            saveLastMove(nil)
            statusMessage = "Move undone."
        } catch {
            userError = "Could not undo the last move: \(error.localizedDescription)"
        }
    }

    func startDownloadsCleanup() {
        beginCleanup(at: downloadsDirectoryURL)
    }

    func chooseCleanupFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to clean up"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        beginCleanup(at: url)
    }

    func setCleanupDestination(entryID: String, destinationID: String) {
        guard let index = cleanupRows.firstIndex(where: { $0.id == entryID }) else { return }
        cleanupRows[index].destinationID = destinationID.isEmpty ? nil : destinationID
        cleanupRows[index].suggestionReason = nil
        cleanupRows[index].isSelected = !destinationID.isEmpty
        refreshFolderGroups()
    }

    func setCleanupSelected(entryID: String, selected: Bool) {
        guard let index = cleanupRows.firstIndex(where: { $0.id == entryID }) else { return }
        cleanupRows[index].isSelected = selected
    }

    func setTrashSelected(entryID: String, selected: Bool) {
        guard let index = trashRows.firstIndex(where: { $0.id == entryID }) else { return }
        trashRows[index].isSelected = selected
    }

    func setFolderGroupSelected(id: String, selected: Bool) {
        if selected { selectedGroupIDs.insert(id) } else { selectedGroupIDs.remove(id) }
    }

    func renameFolderGroup(id: String, to name: String) {
        guard let index = folderGroups.firstIndex(where: { $0.id == id }) else { return }
        folderGroups[index].name = name
    }

    func setMinimumRelatedFileCount(_ count: Int) {
        folderGroupingSettings.minimumRelatedFiles = count
        minimumRelatedFileCount = folderGroupingSettings.minimumRelatedFiles
        refreshFolderGroups()
    }

    func moveSelectedCleanupItems() {
        var movedCount = 0
        var receipts: [FileMoveReceipt] = []
        var createdFolders: [URL] = []

        for row in cleanupRows where row.isSelected {
            guard let destinationID = row.destinationID,
                  let destination = resolvedURL(for: destinationID) else { continue }
            do {
                let receipt = try move(row.url, into: destination)
                receipts.append(receipt)
                remember(file: row.url, destinationID: destinationID)
                movedCount += 1
            } catch {
                userError = "Could not move \(row.url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        if !selectedGroupIDs.isEmpty, let parent = cleanupFolder {
            for group in folderGroups where selectedGroupIDs.contains(group.id) {
                guard let safeName = validFolderName(group.name) else {
                    userError = "Enter a valid name for the \(group.id) folder."
                    continue
                }
                var createdFolderURL: URL?
                var folderWasCreated = false
                var groupReceipts: [FileMoveReceipt] = []
                do {
                    let (newFolder, wasCreated) = try createOrFindFolder(named: safeName, in: parent)
                    createdFolderURL = newFolder
                    folderWasCreated = wasCreated
                    for file in group.files {
                        let receipt = try move(file, into: newFolder)
                        groupReceipts.append(receipt)
                        receipts.append(receipt)
                        movedCount += 1
                    }
                    if wasCreated && !groupReceipts.isEmpty { createdFolders.append(newFolder) }
                } catch {
                    if folderWasCreated, let createdFolderURL {
                        if groupReceipts.isEmpty { removeFolderIfEmpty(createdFolderURL) }
                        else { createdFolders.append(createdFolderURL) }
                    }
                    userError = "Could not organize the \(group.name) group: \(error.localizedDescription)"
                }
            }
        }

        if !receipts.isEmpty {
            saveLastMove(MoveBatchReceipt(moves: receipts, createdFolders: createdFolders))
        }
        selectedGroupIDs.removeAll()
        if let cleanupFolder { beginCleanup(at: cleanupFolder) }
        statusMessage = movedCount == 0 ? "No files were moved." : "Moved \(movedCount) item(s)."
    }

    /// The only app path that sends an item to Trash. The UI calls it only after an explicit, separate confirmation.
    func moveSelectedInstallersToTrash() {
        var trashedCount = 0
        var receipts: [FileMoveReceipt] = []
        for entry in trashRows where entry.isSelected {
            var result: NSURL?
            let sourceScope = entry.url.startAccessingSecurityScopedResource()
            do {
                defer { if sourceScope { entry.url.stopAccessingSecurityScopedResource() } }
                try fileManager.trashItem(at: entry.url, resultingItemURL: &result)
                let movedURL = (result as URL?) ?? entry.url
                receipts.append(FileMoveReceipt(originalURL: entry.url, movedURL: movedURL))
                trashedCount += 1
            } catch {
                userError = "Could not move \(entry.url.lastPathComponent) to Trash: \(error.localizedDescription)"
            }
        }
        if !receipts.isEmpty { saveLastMove(MoveBatchReceipt(moves: receipts)) }
        if let cleanupFolder { beginCleanup(at: cleanupFolder) }
        statusMessage = trashedCount == 0 ? "No installers were moved to Trash." : "Moved \(trashedCount) installer(s) to Trash."
    }

    private var downloadsDirectoryURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
    }

    private func beginCleanup(at folder: URL) {
        if cleanupScopeURL?.standardizedFileURL != folder.standardizedFileURL {
            if cleanupScopeIsActive { cleanupScopeURL?.stopAccessingSecurityScopedResource() }
            cleanupScopeURL = folder
            cleanupScopeIsActive = folder.startAccessingSecurityScopedResource()
        }
        cleanupFolder = folder
        cleanupRows = []
        trashRows = []
        folderGroups = []
        selectedGroupIDs = []

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let isDownloads = folder.standardizedFileURL == downloadsDirectoryURL.standardizedFileURL
            let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            let installedApps = isDownloads ? installedApplications(in: applicationsURL) : []
            let policy = TrashPolicy()

            for url in urls {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { continue }

                if isDownloads,
                   let trashSuggestion = policy.suggestion(
                       for: url,
                       downloadsFolder: downloadsDirectoryURL,
                       applicationsFolder: applicationsURL,
                       installedApps: installedApps
                   ) {
                    trashRows.append(TrashEntry(url: trashSuggestion.fileURL, reason: trashSuggestion.reason, isSelected: false))
                    continue
                }

                let suggestion = SuggestionEngine.suggest(
                    fileName: url.lastPathComponent,
                    destinations: destinations,
                    rules: rules,
                    learning: learning,
                    isScreenCapture: ScreenshotMetadata.isScreenCapture(at: url)
                )
                cleanupRows.append(CleanupEntry(
                    url: url,
                    destinationID: suggestion?.destinationID,
                    suggestionReason: suggestion?.reason,
                    isSelected: suggestion != nil
                ))
            }
            cleanupRows.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            trashRows.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            refreshFolderGroups()
        } catch {
            userError = "Could not read that folder: \(error.localizedDescription)"
        }
    }

    private func refreshFolderGroups() {
        let unassignedFiles = cleanupRows.filter { $0.destinationID == nil }.map(\.url)
        folderGroups = FolderGrouping.suggest(for: unassignedFiles, minimumGroupSize: minimumRelatedFileCount)
        selectedGroupIDs = selectedGroupIDs.intersection(Set(folderGroups.map(\.id)))
    }

    private func installedApplications(in folder: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return contents.filter { url in
            guard url.pathExtension.lowercased() == "app",
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
            return values.isDirectory == true
        }
    }

    private func createOrFindFolder(named name: String, in parent: URL) throws -> (URL, Bool) {
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        if fileManager.fileExists(atPath: candidate.path) {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue { return (candidate, false) }
            var suffix = 2
            repeat {
                candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
                suffix += 1
            } while fileManager.fileExists(atPath: candidate.path)
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        return (candidate, true)
    }

    private func validFolderName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return nil }
        return name
    }

    private func removeFolderIfEmpty(_ url: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path), contents.isEmpty else { return }
        try? fileManager.removeItem(at: url)
    }

    private func move(_ source: URL, into destination: URL) throws -> FileMoveReceipt {
        let sourceAccess = source.startAccessingSecurityScopedResource()
        let destinationAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if sourceAccess { source.stopAccessingSecurityScopedResource() }
            if destinationAccess { destination.stopAccessingSecurityScopedResource() }
        }
        return try mover.move(source, to: destination)
    }

    private func remember(file: URL, destinationID: String) {
        let ext = file.pathExtension.lowercased()
        let tokens = SuggestionEngine.filenameTokens(file.lastPathComponent)
        let entry = LearningRecord(fileExtension: ext, tokens: tokens, destinationID: destinationID, sampleName: file.lastPathComponent)
        learning.removeAll {
            $0.fileExtension == ext && $0.destinationID == destinationID && $0.sampleName == file.lastPathComponent
        }
        learning.insert(entry, at: 0)
        if learning.count > 300 { learning = Array(learning.prefix(300)) }
        persist(learning, key: learningKey)
    }

    private func saveLastMove(_ receipt: MoveBatchReceipt?) {
        lastMove = receipt
        guard let receipt else {
            defaults.removeObject(forKey: lastMoveKey)
            return
        }
        persist(receipt, key: lastMoveKey)
    }

    private func resolvedURL(for id: String) -> URL? {
        guard let index = favoriteFolders.firstIndex(where: { $0.id == id }) else { return nil }
        let folder = favoriteFolders[index]
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let updated = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            favoriteFolders[index].bookmarkData = updated
            persist(favoriteFolders, key: foldersKey)
        }
        return url
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
