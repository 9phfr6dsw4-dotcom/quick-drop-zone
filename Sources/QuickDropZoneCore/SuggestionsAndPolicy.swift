import Foundation

public struct Destination: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DestinationRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var extensions: Set<String>
    public var keywords: [String]
    public var destinationID: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        extensions: Set<String> = [],
        keywords: [String] = [],
        destinationID: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.extensions = Set(extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty })
        self.keywords = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.destinationID = destinationID
        self.isEnabled = isEnabled
    }
}

public struct LearningRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var fileExtension: String
    public var tokens: Set<String>
    public var destinationID: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        fileExtension: String,
        tokens: Set<String>,
        destinationID: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fileExtension = fileExtension.lowercased()
        self.tokens = Set(tokens.map { $0.lowercased() })
        self.destinationID = destinationID
        self.updatedAt = updatedAt
    }
}

public struct DestinationSuggestion: Equatable {
    public let destinationID: String
    public let reason: String

    public init(destinationID: String, reason: String) {
        self.destinationID = destinationID
        self.reason = reason
    }
}

public enum SuggestionEngine {
    public static func suggest(
        fileName: String,
        destinations: [Destination],
        rules: [DestinationRule],
        learning: [LearningRecord]
    ) -> DestinationSuggestion? {
        guard !destinations.isEmpty else { return nil }
        let extensionName = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let availableIDs = Set(destinations.map(\.id))
        let tokens = filenameTokens(fileName)

        if let rule = rules.first(where: { rule in
            guard rule.isEnabled, availableIDs.contains(rule.destinationID) else { return false }
            let extensionMatches = rule.extensions.isEmpty || rule.extensions.contains(extensionName)
            let keywordMatches = rule.keywords.isEmpty || rule.keywords.contains { keyword in
                fileName.localizedCaseInsensitiveContains(keyword)
            }
            return extensionMatches && keywordMatches
        }) {
            return DestinationSuggestion(destinationID: rule.destinationID, reason: "Matched rule: \(rule.name)")
        }

        let scoredLearning: [(record: LearningRecord, score: Int)] = learning.compactMap { record in
            guard availableIDs.contains(record.destinationID) else { return nil }
            let extensionScore: Int = (!extensionName.isEmpty && record.fileExtension == extensionName) ? 1 : 0
            let overlapCount = tokens.intersection(record.tokens).count
            let score = extensionScore + (overlapCount * 2)
            return (record: record, score: score)
        }
        let learnedMatch = scoredLearning
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.record.updatedAt > rhs.record.updatedAt : lhs.score > rhs.score
            }
            .first
        if let learnedMatch {
            return DestinationSuggestion(destinationID: learnedMatch.record.destinationID, reason: "Based on similar files you organized")
        }

        return builtInSuggestion(fileName: fileName, extensionName: extensionName, tokens: tokens, destinations: destinations)
    }

    public static func filenameTokens(_ text: String) -> Set<String> {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let ignored: Set<String> = ["the", "and", "for", "from", "with", "your", "copy", "final", "document"]
        return Set(words.filter { $0.count > 2 && !ignored.contains($0) })
    }

    private static func builtInSuggestion(
        fileName: String,
        extensionName: String,
        tokens: Set<String>,
        destinations: [Destination]
    ) -> DestinationSuggestion? {
        let folderMatchers: [(Set<String>, Set<String>, String)] = [
            (["pdf"], ["bill", "bills", "invoice", "receipt", "receipts", "payment"], "Invoice or bill PDF"),
            (["pdf"], ["tax", "taxes"], "Tax document PDF"),
            (["pdf", "doc", "docx", "xls", "xlsx"], ["car", "vehicle", "automotive", "auto", "maintenance", "registration"], "Vehicle-related document"),
            (["png", "jpg", "jpeg", "heic", "webp"], ["screenshot", "screenshots"], "Screenshot image")
        ]

        for (extensions, triggers, reason) in folderMatchers where extensions.contains(extensionName) && !tokens.isDisjoint(with: triggers) {
            if let destination = destinations.first(where: { folderName in
                let folderTokens = filenameTokens(folderName.name)
                return !folderTokens.isDisjoint(with: triggers)
            }) {
                return DestinationSuggestion(destinationID: destination.id, reason: reason)
            }
        }

        let categoryByExtension: [String: Set<String>] = [
            "pdf": ["pdf", "document", "documents"],
            "png": ["image", "images", "picture", "pictures", "screenshot", "screenshots"],
            "jpg": ["image", "images", "picture", "pictures"],
            "jpeg": ["image", "images", "picture", "pictures"],
            "heic": ["image", "images", "picture", "pictures"],
            "doc": ["document", "documents"],
            "docx": ["document", "documents"],
            "csv": ["spreadsheet", "spreadsheets", "finance"],
            "xlsx": ["spreadsheet", "spreadsheets", "finance"],
            "zip": ["archive", "archives"]
        ]
        guard let categoryTokens = categoryByExtension[extensionName] else { return nil }
        guard let destination = destinations.first(where: { !filenameTokens($0.name).isDisjoint(with: categoryTokens) }) else { return nil }
        return DestinationSuggestion(destinationID: destination.id, reason: "Matched file type: .\(extensionName)")
    }
}

public struct TrashSuggestion: Equatable {
    public let fileURL: URL
    public let reason: String

    public init(fileURL: URL, reason: String) {
        self.fileURL = fileURL
        self.reason = reason
    }
}

/// This is intentionally narrow: only an installed app's matching .dmg directly in Downloads qualifies.
public struct TrashPolicy {
    public init() {}

    public func suggestion(
        for fileURL: URL,
        downloadsFolder: URL,
        applicationsFolder: URL,
        installedApps: [URL]
    ) -> TrashSuggestion? {
        guard fileURL.pathExtension.lowercased() == "dmg" else { return nil }
        guard fileURL.deletingLastPathComponent().standardizedFileURL == downloadsFolder.standardizedFileURL else { return nil }

        let installerName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let app = installedApps.first(where: { appURL in
            guard appURL.pathExtension.lowercased() == "app",
                  appURL.deletingLastPathComponent().standardizedFileURL == applicationsFolder.standardizedFileURL else { return false }
            let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
            guard installerName.hasPrefix(appName) else { return false }
            let remainder = installerName.dropFirst(appName.count)
            guard let first = remainder.first else { return true }
            return first.isWhitespace || first == "-" || first == "_" || first == "." || first == "(" || first.isNumber
        }) else { return nil }

        let installedName = app.deletingPathExtension().lastPathComponent
        return TrashSuggestion(fileURL: fileURL, reason: "\(installedName) is already installed in Applications")
    }
}

public struct FolderGroup: Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let files: [URL]

    public init(name: String, files: [URL]) {
        self.name = name
        self.files = files
    }
}

public enum FolderGrouping {
    public static func suggest(for files: [URL], minimumGroupSize: Int = 2) -> [FolderGroup] {
        var groups: [String: [URL]] = [:]
        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            let date = values?.contentModificationDate ?? .distantPast
            let year = Calendar.current.component(.year, from: date)
            let name = suggestedName(for: file, year: year)
            groups[name, default: []].append(file)
        }
        return groups
            .filter { $0.value.count >= max(2, minimumGroupSize) }
            .map { FolderGroup(name: $0.key, files: $0.value.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func suggestedName(for file: URL, year: Int) -> String {
        let filename = file.lastPathComponent.lowercased()
        let ext = file.pathExtension.lowercased()
        if filename.contains("screenshot") || filename.contains("screen shot") { return "Screenshots" }
        if ext == "pdf" { return "PDFs \(year)" }
        if ["png", "jpg", "jpeg", "heic", "webp"].contains(ext) { return "Images \(year)" }
        if ext == "doc" || ext == "docx" { return "Documents \(year)" }
        guard !ext.isEmpty else { return "Other Files \(year)" }
        return "\(ext.uppercased()) Files \(year)"
    }
}
