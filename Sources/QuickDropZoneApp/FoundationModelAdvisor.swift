import Foundation
import QuickDropZoneCore
#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationModelAdvisor {
    static func suggest(fileName: String, destinations: [Destination]) async -> DestinationSuggestion? {
        guard !destinations.isEmpty else { return nil }
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let allowedNames = destinations.map(\.name)
        let prompt = """
        Choose the single best existing destination folder for organizing this file. Use only the filename and the allowed folder names. Do not invent a folder. Return only the exact folder name, with no explanation.
        Filename: \(fileName)
        Allowed folders: \(allowedNames.joined(separator: ", "))
        """
        let session = LanguageModelSession(instructions: "Classify filenames conservatively. Select only one supplied folder name, or return NONE when no folder is a reasonable match. Do not request tools or external information.")
        do {
            let response = try await session.respond(to: prompt)
            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            guard let destination = destinations.first(where: { $0.name.caseInsensitiveCompare(answer) == .orderedSame }) else { return nil }
            return DestinationSuggestion(destinationID: destination.id, reason: "Suggested by Apple’s on-device model")
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
