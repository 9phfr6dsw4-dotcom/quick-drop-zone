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
        let learning = [
            LearningRecord(fileExtension: "pdf", tokens: ["acme", "invoice", "jan"], destinationID: "taxes"),
            LearningRecord(fileExtension: "pdf", tokens: ["acme", "invoice", "feb"], destinationID: "taxes"),
            LearningRecord(fileExtension: "pdf", tokens: ["acme", "invoice", "mar"], destinationID: "taxes")
        ]

        let suggestion = SuggestionEngine.suggest(
            fileName: "Acme utility April.pdf",
            destinations: destinations,
            rules: [],
            learning: learning
        )

        XCTAssertEqual(suggestion?.destinationID, "taxes")
        XCTAssertTrue(suggestion?.reason.localizedCaseInsensitiveContains("similar") == true)
    }

    func testFilenameScreenshotFallbackIsLimitedToPNG() {
        let destination = [Destination(id: "screenshots", name: "Screenshots")]
        for fileName in ["Screenshot 01.jpg", "Screen Shot 02.heic", "Screenshot 03.pdf"] {
            XCTAssertNil(SuggestionEngine.suggest(fileName: fileName, destinations: destination, rules: [], learning: []))
        }
    }

    func testMacScreenshotMetadataMatchesPNGRuleEvenWithoutScreenshotName() {
        let rule = DestinationRule(name: "PNG screenshots", extensions: ["png"], keywords: ["screenshot"], destinationID: "screenshots")
        let suggestion = SuggestionEngine.suggest(
            fileName: "capture-2026-04-01.png",
            destinations: [Destination(id: "screenshots", name: "Screenshots")],
            rules: [rule],
            learning: [],
            isScreenCapture: true
        )
        XCTAssertEqual(suggestion?.destinationID, "screenshots")
        XCTAssertEqual(suggestion?.reason, "Matches your PNG screenshots rule")
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

    func testPNGOnlyScreenshotRuleDoesNotLeakToOtherImageTypes() {
        let destinations = [Destination(id: "screenshots", name: "Screenshots")]
        let rule = DestinationRule(name: "PNG screenshots", extensions: ["png"], keywords: ["screenshot"], destinationID: "screenshots")

        for fileName in ["Screenshot 01.jpg", "Screenshot 02.heic", "Screenshot 03.webp"] {
            let suggestion = SuggestionEngine.suggest(fileName: fileName, destinations: destinations, rules: [rule], learning: [])
            XCTAssertNil(suggestion, "A PNG-only Screenshots rule must not suggest \(fileName)")
        }
    }

    func testNonScreenshotPNGDoesNotMatchScreenshotsFolderByTypeAlone() {
        let suggestion = SuggestionEngine.suggest(
            fileName: "product-photo.png",
            destinations: [Destination(id: "screenshots", name: "Screenshots")],
            rules: [],
            learning: []
        )
        XCTAssertNil(suggestion)
    }

    func testOneLearnedExtensionOrSharedTokenIsNotAConfidentSuggestion() {
        let destinations = [Destination(id: "screenshots", name: "Screenshots")]
        let singleExtensionExample = [LearningRecord(fileExtension: "png", tokens: ["invoice", "acme"], destinationID: "screenshots")]
        let extensionOnly = SuggestionEngine.suggest(
            fileName: "random-photo.png",
            destinations: destinations,
            rules: [],
            learning: singleExtensionExample
        )
        XCTAssertNil(extensionOnly)

        let tokenOnly = SuggestionEngine.suggest(
            fileName: "acme-random.png",
            destinations: destinations,
            rules: [],
            learning: singleExtensionExample
        )
        XCTAssertNil(tokenOnly)
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

    func testFolderGroupingRequiresSharedMeaningfulSubjectNotTypeOrDate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let related = [
            root.appendingPathComponent("Acme Invoice Jan.pdf"),
            root.appendingPathComponent("Acme Contract Renewal.docx"),
            root.appendingPathComponent("Acme Receipt Feb.pdf")
        ]
        let unrelated = [
            root.appendingPathComponent("Northstar brief.pdf"),
            root.appendingPathComponent("Contoso proposal.pdf"),
            root.appendingPathComponent("Screenshot 1.png"),
            root.appendingPathComponent("Screen Shot 2.png")
        ]
        for url in related + unrelated { try Data().write(to: url) }

        let groups = FolderGrouping.suggest(for: related + unrelated)
        XCTAssertEqual(groups.map(\.name), ["Acme"])
        XCTAssertEqual(groups.first?.files.count, 3)
        XCTAssertTrue(groups.allSatisfy { $0.files.allSatisfy { related.contains($0) } })

        try FileManager.default.removeItem(at: root)
    }
}
