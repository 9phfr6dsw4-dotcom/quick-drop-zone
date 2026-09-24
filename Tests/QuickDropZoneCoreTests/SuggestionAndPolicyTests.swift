import Foundation
import XCTest
@testable import QuickDropZoneCore

final class SuggestionAndPolicyTests: XCTestCase {
    func testExplicitRuleRoutesInvoicePDFToBills() {
        let destinations = [Destination(id: "bills", name: "Bills")]
        let rules = [DestinationRule(
            name: "Invoices",
            extensions: ["pdf"],
            keywords: ["bill", "invoice"],
            destinationID: "bills"
        )]

        let suggestion = SuggestionEngine.suggest(
            fileName: "March invoice.pdf",
            destinations: destinations,
            rules: rules,
            learning: []
        )

        XCTAssertEqual(suggestion?.destinationID, "bills")
        XCTAssertTrue(suggestion?.reason.localizedCaseInsensitiveContains("rule") == true)
    }

    func testLearningUsesExtensionAndFilenameTokens() {
        let destinations = [Destination(id: "taxes", name: "Taxes")]
        let learning = [LearningRecord(fileExtension: "pdf", tokens: ["irs", "tax"], destinationID: "taxes")]

        let suggestion = SuggestionEngine.suggest(
            fileName: "IRS tax statement.pdf",
            destinations: destinations,
            rules: [],
            learning: learning
        )

        XCTAssertEqual(suggestion?.destinationID, "taxes")
        XCTAssertTrue(suggestion?.reason.localizedCaseInsensitiveContains("similar") == true)
    }

    func testBuiltInSuggestionMatchesBillsFolderForInvoicePDF() {
        let suggestion = SuggestionEngine.suggest(
            fileName: "utility-invoice.pdf",
            destinations: [Destination(id: "d1", name: "Bills")],
            rules: [],
            learning: []
        )
        XCTAssertEqual(suggestion?.destinationID, "d1")
    }

    func testTrashPolicyOnlyAllowsInstalledAppDiskImagesDirectlyInDownloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let applications = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let app = applications.appendingPathComponent("Firefox.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let installed = [app]
        let policy = TrashPolicy()

        let eligible = downloads.appendingPathComponent("Firefox 130.dmg")
        let otherDMG = downloads.appendingPathComponent("Unrelated.dmg")
        let outsideDownloads = root.appendingPathComponent("Firefox.dmg")
        let otherType = downloads.appendingPathComponent("Firefox.zip")

        XCTAssertNotNil(policy.suggestion(for: eligible, downloadsFolder: downloads, applicationsFolder: applications, installedApps: installed))
        XCTAssertNil(policy.suggestion(for: otherDMG, downloadsFolder: downloads, applicationsFolder: applications, installedApps: installed))
        XCTAssertNil(policy.suggestion(for: outsideDownloads, downloadsFolder: downloads, applicationsFolder: applications, installedApps: installed))
        XCTAssertNil(policy.suggestion(for: otherType, downloadsFolder: downloads, applicationsFolder: applications, installedApps: installed))

        try FileManager.default.removeItem(at: root)
    }

    func testFolderGroupingSuggestsScreenshotsAndYearBasedPDFsOnlyForGroups() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("invoice-a.pdf")
        let b = root.appendingPathComponent("invoice-b.pdf")
        let c = root.appendingPathComponent("Screenshot 1.png")
        let d = root.appendingPathComponent("Screen Shot 2.png")
        let isolated = root.appendingPathComponent("notes.txt")
        for url in [a, b, c, d, isolated] { try Data().write(to: url) }
        let date = ISO8601DateFormatter().date(from: "2025-06-01T12:00:00Z")!
        for url in [a, b] { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }

        let groups = FolderGrouping.suggest(for: [a, b, c, d, isolated])
        XCTAssertEqual(Set(groups.map(\.name)), Set(["PDFs 2025", "Screenshots"]))
        XCTAssertEqual(groups.first(where: { $0.name == "PDFs 2025" })?.files.count, 2)
        XCTAssertFalse(groups.contains(where: { $0.files.contains(isolated) }))

        try FileManager.default.removeItem(at: root)
    }
}
