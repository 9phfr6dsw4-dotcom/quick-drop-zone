import Foundation
import XCTest
@testable import QuickDropZoneCore

final class FileMoveTests: XCTestCase {
    private func makeSandbox() throws -> (root: URL, source: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickDropZoneTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, source, destination)
    }

    func testMoveThenUndoRestoresOriginalFile() throws {
        let box = try makeSandbox()
        let original = box.source.appendingPathComponent("report.pdf")
        try Data("private test content".utf8).write(to: original)
        let mover = FileMoveService()

        let receipt = try mover.move(original, to: box.destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: receipt.movedURL), Data("private test content".utf8))

        try mover.undo(receipt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: receipt.movedURL.path))
    }

    func testMoveUsesUniqueNameInsteadOfOverwriting() throws {
        let box = try makeSandbox()
        let original = box.source.appendingPathComponent("report.pdf")
        try Data("new".utf8).write(to: original)
        try Data("existing".utf8).write(to: box.destination.appendingPathComponent("report.pdf"))

        let receipt = try FileMoveService().move(original, to: box.destination)

        XCTAssertEqual(receipt.movedURL.lastPathComponent, "report 2.pdf")
        XCTAssertEqual(try String(contentsOf: box.destination.appendingPathComponent("report.pdf"), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: receipt.movedURL, encoding: .utf8), "new")
    }

    func testMoveRejectsDirectoriesAndUndoWillNotOverwriteOriginal() throws {
        let box = try makeSandbox()
        let folder = box.source.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mover = FileMoveService()
        XCTAssertThrowsError(try mover.move(folder, to: box.destination))

        let original = box.source.appendingPathComponent("notes.txt")
        try Data("source".utf8).write(to: original)
        let receipt = try mover.move(original, to: box.destination)
        try Data("replacement".utf8).write(to: original)
        XCTAssertThrowsError(try mover.undo(receipt))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "replacement")
    }
}
