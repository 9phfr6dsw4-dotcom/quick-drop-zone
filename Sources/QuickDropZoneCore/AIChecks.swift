import Foundation

/// Apple Intelligence's checked answer about one file.
public struct FileDecision: Equatable, Sendable {
    /// One of your folders, or nil when it had no good match.
    public var destinationID: String?
    public var isConfident: Bool
    public var reason: String
    /// A clearer file name (already checked), or nil.
    public var proposedName: String?
    /// One or two sentences on what the file is.
    public var summary: String

    public init(destinationID: String?, isConfident: Bool, reason: String, proposedName: String?, summary: String) {
        self.destinationID = destinationID
        self.isConfident = isConfident
        self.reason = reason
        self.proposedName = proposedName
        self.summary = summary
    }
}

/// Turns raw model answers into safe values. Anything that doesn't fit is dropped, so a confused
/// answer can never send a file somewhere unexpected or give it a strange name.
public enum DecisionCheck {
    /// The folder the model named, if it's exactly one of yours and no rule reserves it.
    public static func destination(for answer: String, destinations: [Destination], locked: Set<String>) -> Destination? {
        let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.lowercased() != "none", clean.lowercased() != "unknown" else { return nil }
        let matches = destinations.filter { $0.name.compare(clean, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        guard matches.count == 1, let match = matches.first, !locked.contains(match.id) else { return nil }
        return match
    }

    public static func check(folder: String, confidence: String, reason: String, betterName: String, summary: String,
                             fileName: String, destinations: [Destination], locked: Set<String>) -> FileDecision {
        let match = Self.destination(for: folder, destinations: destinations, locked: locked)
        let sure = confidence.lowercased().contains("high")
        return FileDecision(destinationID: match?.id, isConfident: match != nil && sure,
                            reason: oneLine(reason, limit: 160, fallback: "Apple Intelligence's best match."),
                            proposedName: RenameCheck.acceptedName(original: fileName, proposed: betterName),
                            summary: oneLine(summary, limit: 300, fallback: ""))
    }

    public static func oneLine(_ text: String, limit: Int, fallback: String) -> String {
        let clean = TextTools.collapseWhitespace(text)
        guard !clean.isEmpty else { return fallback }
        return clean.count > limit ? String(clean.prefix(limit - 1)) + "…" : clean
    }
}

public enum RenameCheck {
    private static let forbidden = CharacterSet(charactersIn: "/\\:")
    private static let generic: Set<String> = ["document", "file", "untitled", "image", "photo", "screenshot", "scan", "download", "new file", "copy"]

    /// A safe new name that keeps the original extension, or nil when the proposal is unusable or
    /// the same as the current name.
    public static func acceptedName(original: String, proposed: String) -> String? {
        let originalExtension = URL(fileURLWithPath: original).pathExtension
        var stem = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))
        guard !stem.contains("\n"), !stem.contains("\r") else { return nil }
        if !originalExtension.isEmpty, stem.lowercased().hasSuffix("." + originalExtension.lowercased()) {
            stem = String(stem.dropLast(originalExtension.count + 1))
        }
        var kept = String.UnicodeScalarView()
        for scalar in stem.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) && !forbidden.contains(scalar) {
            kept.append(scalar)
        }
        stem = String(kept)
        stem = TextTools.collapseWhitespace(stem).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard (2...80).contains(stem.count), stem.filter(\.isLetter).count >= 2,
              !generic.contains(stem.lowercased()) else { return nil }
        let name = originalExtension.isEmpty ? stem : stem + "." + originalExtension
        return name == original ? nil : name
    }
}

/// A new folder Apple Intelligence proposed for a cleanup, after checking.
public struct FolderGroupProposal: Equatable, Sendable {
    public var name: String
    /// Positions in the file list given to the model (0-based).
    public var indexes: [Int]

    public init(name: String, indexes: [Int]) {
        self.name = name
        self.indexes = indexes
    }
}

public enum GroupCheck {
    public static func validFolderName(_ value: String) -> String? {
        let name = TextTools.collapseWhitespace(value).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard (2...40).contains(name.count), name != ".", name != "..", name.filter(\.isLetter).count >= 2,
              !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return nil }
        return name
    }

    /// Keeps only groups with a valid name and at least `minimumSize` files. File numbers from the
    /// model start at 1; each file can be in one group only (the first one that claims it), unknown
    /// numbers are ignored, and two groups can't share a name. At most 8 groups.
    public static func validate(_ groups: [(name: String, members: [Int])], fileCount: Int, minimumSize: Int) -> [FolderGroupProposal] {
        var used: Set<Int> = []
        var names: Set<String> = []
        var result: [FolderGroupProposal] = []
        for group in groups {
            guard result.count < 8, let name = validFolderName(group.name), !names.contains(name.lowercased()) else { continue }
            var indexes: [Int] = []
            for member in group.members where member >= 1 && member <= fileCount {
                let index = member - 1
                if !used.contains(index), !indexes.contains(index) { indexes.append(index) }
            }
            guard indexes.count >= max(2, minimumSize) else { continue }
            used.formUnion(indexes)
            names.insert(name.lowercased())
            result.append(FolderGroupProposal(name: name, indexes: indexes.sorted()))
        }
        return result
    }
}

/// The prompt for one file: its facts, your folders, and how you filed similar files before.
public enum DecisionPrompt {
    public static func examples(learning: [LearningRecord], destinations: [Destination], locked: Set<String>, limit: Int = 8) -> [String] {
        var seen: Set<String> = []
        var lines: [String] = []
        for record in learning.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard lines.count < limit, let sample = record.sampleName, !locked.contains(record.destinationID),
                  let folder = destinations.first(where: { $0.id == record.destinationID }) else { continue }
            let key = sample.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            lines.append("“\(TextTools.redactLongNumbers(sample))” → \(folder.name)")
        }
        return lines
    }

    public static func make(facts: FileFacts, destinations: [Destination], locked: Set<String>, examples: [String]) -> String {
        let allowed = destinations.filter { !locked.contains($0.id) }.map(\.name)
        var lines = ["Decide where this file belongs.", facts.promptText()]
        lines.append("Folders you may choose (exact names): \(allowed.joined(separator: " | "))")
        if !examples.isEmpty {
            lines.append("How this person filed files before:")
            lines += examples.map { "- " + $0 }
        }
        lines.append("Answer none for the folder if no folder clearly fits.")
        return lines.joined(separator: "\n")
    }
}
