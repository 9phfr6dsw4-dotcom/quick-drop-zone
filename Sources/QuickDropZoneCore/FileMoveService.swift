import Foundation

public struct FileMoveReceipt: Codable, Equatable {
    public let originalURL: URL
    public let movedURL: URL

    public init(originalURL: URL, movedURL: URL) {
        self.originalURL = originalURL
        self.movedURL = movedURL
    }
}

public enum FileMoveError: Error, Equatable {
    case sourceDoesNotExist
    case sourceIsDirectory
    case destinationIsNotDirectory
    case sourceAlreadyInDestination
    case movedFileDoesNotExist
    case originalPathOccupied
}

/// Performs one explicit file move and records enough information to undo it.
/// The UI must call `move` only after the user confirms the destination.
public struct FileMoveService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func move(_ sourceURL: URL, to destinationFolderURL: URL) throws -> FileMoveReceipt {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileMoveError.sourceDoesNotExist
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw FileMoveError.sourceDoesNotExist
        }
        guard !isDirectory.boolValue else {
            throw FileMoveError.sourceIsDirectory
        }

        var destinationIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationFolderURL.path, isDirectory: &destinationIsDirectory),
              destinationIsDirectory.boolValue else {
            throw FileMoveError.destinationIsNotDirectory
        }

        let sourceParent = sourceURL.deletingLastPathComponent().standardizedFileURL
        let destinationParent = destinationFolderURL.standardizedFileURL
        guard sourceParent != destinationParent else {
            throw FileMoveError.sourceAlreadyInDestination
        }

        let targetURL = uniqueDestination(for: sourceURL, in: destinationFolderURL)
        try fileManager.moveItem(at: sourceURL, to: targetURL)
        return FileMoveReceipt(originalURL: sourceURL, movedURL: targetURL)
    }

    public func undo(_ receipt: FileMoveReceipt) throws {
        guard fileManager.fileExists(atPath: receipt.movedURL.path) else {
            throw FileMoveError.movedFileDoesNotExist
        }
        guard !fileManager.fileExists(atPath: receipt.originalURL.path) else {
            throw FileMoveError.originalPathOccupied
        }
        try fileManager.moveItem(at: receipt.movedURL, to: receipt.originalURL)
    }

    private func uniqueDestination(for sourceURL: URL, in folderURL: URL) -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let filename = ext.isEmpty ? "\(name) \(suffix)" : "\(name) \(suffix).\(ext)"
            candidate = folderURL.appendingPathComponent(filename)
            suffix += 1
        }
        return candidate
    }
}
