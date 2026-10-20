import Foundation
import XCTest
@testable import QuickDropZoneCore

final class LegacyDataMigrationTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "QuickDropZoneTests.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    func testCopiesTheAppsOwnKeysAndSparkleUserChoices() {
        let legacy: [String: Any] = [
            "QuickDropZone.favoriteFolders.v1": Data([1, 2, 3]),
            "QuickDropZone.autoMove": false,
            "QuickDropZone.hasLaunched.v2": true,
            "SUEnableAutomaticChecks": false,
            "SUAutomaticallyUpdate": true
        ]
        XCTAssertEqual(
            LegacyDataMigrationPolicy.keysToCopy(legacy: legacy, existing: []),
            [
                "QuickDropZone.autoMove", "QuickDropZone.favoriteFolders.v1", "QuickDropZone.hasLaunched.v2",
                "SUAutomaticallyUpdate", "SUEnableAutomaticChecks"
            ]
        )
    }

    func testLeavesOtherKeysBehind() {
        let legacy: [String: Any] = [
            "SULastCheckTime": Date(),
            "SUSkippedVersion": "2.5.0",
            "SUFeedURL": "https://example.invalid/feed.xml",
            "NSWindow Frame main": "0 0 100 100",
            "QuickDropZone.updateTestMarker": "x"
        ]
        XCTAssertEqual(LegacyDataMigrationPolicy.keysToCopy(legacy: legacy, existing: []), [])
    }

    func testNeverOverwritesWhatLevantAlreadySaved() {
        let legacy: [String: Any] = ["QuickDropZone.autoMove": false, "QuickDropZone.notifications": false]
        XCTAssertEqual(
            LegacyDataMigrationPolicy.keysToCopy(legacy: legacy, existing: ["QuickDropZone.autoMove"]),
            ["QuickDropZone.notifications"]
        )
    }

    func testMigrateWritesValuesAndMarksDone() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "QuickDropZone.notifications")

        let legacy: [String: Any] = [
            "QuickDropZone.autoMove": false,
            "QuickDropZone.notifications": false,
            "QuickDropZone.favoriteFolders.v1": Data([9, 8, 7])
        ]
        let copied = LegacyDataMigrationPolicy.migrate(legacy: legacy, into: defaults)

        XCTAssertEqual(copied, 2)
        XCTAssertEqual(defaults.object(forKey: "QuickDropZone.autoMove") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "QuickDropZone.notifications") as? Bool, true, "Levant's own value wins")
        XCTAssertEqual(defaults.data(forKey: "QuickDropZone.favoriteFolders.v1"), Data([9, 8, 7]))
        XCTAssertTrue(defaults.bool(forKey: LegacyDataMigrationPolicy.doneKey))
    }

    func testMigrateWithNothingToMoveStillMarksDone() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(LegacyDataMigrationPolicy.migrate(legacy: [:], into: defaults), 0)
        XCTAssertTrue(defaults.bool(forKey: LegacyDataMigrationPolicy.doneKey))
    }
}
