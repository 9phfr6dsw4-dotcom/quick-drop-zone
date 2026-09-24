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
    private static let screenshotImageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]
    private static let learningNoise: Set<String> = [
        "the", "and", "for", "from", "with", "your", "copy", "final", "document", "documents",
        "invoice", "invoices", "bill", "bills", "receipt", "receipts", "payment", "statement",
        "screenshot", "screenshots", "screen", "shot", "capture", "image", "photo", "scan",
        "pdf", "png", "jpg", "jpeg", "heic", "tif", "tiff", "doc", "docx", "xls", "xlsx", "csv", "zip",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    public static func suggest(
        fileName: String,
        destinations: [Destination],
        rules: [DestinationRule],
        learning: [LearningRecord],
        isScreenCapture: Bool = false
    ) -> DestinationSuggestion? {
        guard !destinations.isEmpty else { return nil }
        let extensionName = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let availableIDs = Set(destinations.map(\.id))
        let exactTokens = words(in: fileName)
        let tokens = filenameTokens(fileName)
        let isMetadataScreenshot = isScreenCapture && screenshotImageExtensions.contains(extensionName)
        let isFilenameScreenshot = extensionName == "png" && isScreenshotFilename(fileName)
        let isScreenshot = isMetadataScreenshot || isFilenameScreenshot
        let activeRules = rules.filter { $0.isEnabled && availableIDs.contains($0.destinationID) }

        let matchingRule = activeRules.first { rule in
            let extensionMatches = rule.extensions.isEmpty || rule.extensions.contains(extensionName)
            let keywordMatches = rule.keywords.isEmpty || rule.keywords.contains { keyword in
                let keywordTokens = words(in: keyword)
                guard !keywordTokens.isEmpty else { return false }
                if keywordTokens.isSubset(of: exactTokens) { return true }
                return isMetadataScreenshot && keywordTokens == ["screenshot"]
            }
            return extensionMatches && keywordMatches
        }
        if let matchingRule {
            return DestinationSuggestion(destinationID: matchingRule.destinationID, reason: "Matches your \(matchingRule.name) rule")
        }

        // A rule-targeted folder is off-limits to other heuristics when its own rule did not match.
        let lockedDestinationIDs = Set(activeRules.map(\.destinationID))

        let examplesByDestination = Dictionary(grouping: learning.filter { record in
            availableIDs.contains(record.destinationID)
                && !lockedDestinationIDs.contains(record.destinationID)
                && !extensionName.isEmpty
                && record.fileExtension == extensionName
                && !tokens.isDisjoint(with: meaningfulTokens(record.tokens))
        }, by: \.destinationID)
        let repeatedPatterns = examplesByDestination.compactMap { destinationID, examples -> (String, Int)? in
            let distinctExamples = Set(examples.map { $0.tokens.sorted().joined(separator: "|") })
            guard distinctExamples.count >= 3 else { return nil }
            return (destinationID, distinctExamples.count)
        }
        if let learnedMatch = repeatedPatterns.max(by: { $0.1 < $1.1 }) {
            return DestinationSuggestion(
                destinationID: learnedMatch.0,
                reason: "Similar to files you moved before (\(learnedMatch.1) examples)"
            )
        }

        return builtInSuggestion(
            extensionName: extensionName,
            tokens: exactTokens,
            destinations: destinations.filter { !lockedDestinationIDs.contains($0.id) },
            isScreenshot: isScreenshot,
            isFilenameScreenshot: isFilenameScreenshot
        )
    }

    public static func filenameTokens(_ text: String) -> Set<String> {
        meaningfulTokens(words(in: URL(fileURLWithPath: text).deletingPathExtension().lastPathComponent))
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }

    private static func meaningfulTokens(_ tokens: Set<String>) -> Set<String> {
        Set(tokens.filter { token in
            token.count >= 4 && !learningNoise.contains(token) && Int(token) == nil
        })
    }

    private static func isScreenshotFilename(_ fileName: String) -> Bool {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.lowercased()
        return stem == "screenshot" || stem.hasPrefix("screenshot ") || stem.hasPrefix("screenshot-")
            || stem == "screen shot" || stem.hasPrefix("screen shot ") || stem.hasPrefix("screen shot-")
    }

    private static func builtInSuggestion(
        extensionName: String,
        tokens: Set<String>,
        destinations: [Destination],
        isScreenshot: Bool,
        isFilenameScreenshot: Bool
    ) -> DestinationSuggestion? {
        if isScreenshot,
           let destination = destinations.first(where: { words(in: $0.name).contains("screenshots") || words(in: $0.name).contains("screenshot") }) {
            let reason = isFilenameScreenshot ? "Filename matches macOS screenshot naming" : "macOS marks this as a screen capture"
            return DestinationSuggestion(destinationID: destination.id, reason: reason)
        }

        let subjectMatchers: [(Set<String>, Set<String>, Set<String>, String)] = [
            (["pdf", "doc", "docx"], ["bill", "bills", "invoice", "invoices", "receipt", "receipts"], ["bill", "bills", "invoice", "invoices", "receipts", "receipts"], "Matches invoice or bill wording"),
            (["pdf", "doc", "docx"], ["tax", "taxes", "irs"], ["tax", "taxes", "irs"], "Matches tax-document wording"),
            (["pdf", "doc", "docx"], ["car", "vehicle", "automotive", "maintenance", "registration"], ["car", "cars", "vehicle", "vehicles", "automotive"], "Matches vehicle-document wording")
        ]

        for (extensions, filenameTerms, folderTerms, reason) in subjectMatchers
        where extensions.contains(extensionName) && !tokens.isDisjoint(with: filenameTerms) {
            if let destination = destinations.first(where: { !words(in: $0.name).isDisjoint(with: folderTerms) }) {
                return DestinationSuggestion(destinationID: destination.id, reason: reason)
            }
        }
        return nil
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
    public let id: String
    public var name: String
    public let reason: String
    public let files: [URL]

    public init(id: String, name: String, reason: String, files: [URL]) {
        self.id = id
        self.name = name
        self.reason = reason
        self.files = files
    }
}

public enum FolderGrouping {
    public static func suggest(for files: [URL], minimumGroupSize: Int = 2) -> [FolderGroup] {
        var filesBySubject: [String: [URL]] = [:]
        for file in files {
            for subject in SuggestionEngine.filenameTokens(file.lastPathComponent) {
                filesBySubject[subject, default: []].append(file)
            }
        }

        var usedFiles = Set<URL>()
        let minimum = max(2, minimumGroupSize)
        return filesBySubject
            .map { (subject: $0.key, files: Array(Set($0.value))) }
            .sorted { lhs, rhs in
                lhs.files.count == rhs.files.count ? lhs.subject < rhs.subject : lhs.files.count > rhs.files.count
            }
            .compactMap { candidate -> FolderGroup? in
                let remaining = candidate.files.filter { !usedFiles.contains($0) }
                guard remaining.count >= minimum else { return nil }
                remaining.forEach { usedFiles.insert($0) }
                let firstCharacter = String(candidate.subject.prefix(1)).uppercased()
                let remainingCharacters = String(candidate.subject.dropFirst())
                let displayName = firstCharacter + remainingCharacters
                let reason = "These \(remaining.count) files share the subject “\(displayName)” in their filenames."
                return FolderGroup(
                    id: candidate.subject,
                    name: displayName,
                    reason: reason,
                    files: remaining.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                )
            }
    }
}
