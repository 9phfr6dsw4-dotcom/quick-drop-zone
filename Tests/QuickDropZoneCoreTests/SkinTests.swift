import Foundation
import XCTest
@testable import QuickDropZoneCore

final class SkinTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "QuickDropZoneTests.skins.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    func testThereAreEightSkinsWithSlateAndOysterAsDefaults() {
        XCTAssertEqual(Skin.allCases.count, 8)
        XCTAssertEqual(Skin.defaultDark, .slate)
        XCTAssertEqual(Skin.defaultLight, .oyster)
        XCTAssertTrue(Skin.slate.isDark)
        XCTAssertFalse(Skin.oyster.isDark)
        XCTAssertFalse(Skin.mint.isDark)
        XCTAssertEqual(Skin.allCases.filter { !$0.isDark }.count, 2)
    }

    /// Text on the main button and the accent on the window must stay readable in every skin.
    func testEverySkinKeepsItsTextReadable() {
        for skin in Skin.allCases {
            let palette = skin.palette
            XCTAssertGreaterThanOrEqual(RGB.contrast(palette.accent, palette.background), 4.5, "\(skin) accent on background")
            XCTAssertGreaterThanOrEqual(RGB.contrast(palette.accent, palette.sidebar), 4.5, "\(skin) accent on sidebar")
            XCTAssertGreaterThanOrEqual(RGB.contrast(palette.onAccent, palette.accent), 4.5, "\(skin) button text")
            XCTAssertGreaterThanOrEqual(RGB.contrast(palette.onAccent, palette.accentLight), 4.5, "\(skin) button text at the top of the button")
        }
    }

    func testLightSkinsHaveLightBackgrounds() {
        for skin in Skin.allCases {
            let luminance = skin.palette.background.relativeLuminance
            XCTAssertEqual(luminance > 0.5, !skin.isDark, "\(skin)")
        }
    }

    func testFollowingTheMacUsesSlateInDarkModeAndOysterInLightMode() {
        let preference = SkinPreference()
        XCTAssertEqual(preference.resolved(systemIsDark: true), .slate)
        XCTAssertEqual(preference.resolved(systemIsDark: false), .oyster)
    }

    func testAChosenSkinIgnoresTheMacsSetting() {
        var preference = SkinPreference()
        preference.mode = .fixed
        preference = preference.selecting(.mint)
        XCTAssertEqual(preference.resolved(systemIsDark: true), .mint)
        XCTAssertEqual(preference.resolved(systemIsDark: false), .mint)
        preference = preference.selecting(.bordeaux)
        XCTAssertEqual(preference.resolved(systemIsDark: false), .bordeaux)
    }

    func testPickingWhileFollowingTheMacChangesTheSkinForThatKindOfMode() {
        let preference = SkinPreference().selecting(.sky).selecting(.mint)
        XCTAssertEqual(preference.darkSkin, .sky)
        XCTAssertEqual(preference.lightSkin, .mint)
        XCTAssertEqual(preference.resolved(systemIsDark: true), .sky)
        XCTAssertEqual(preference.resolved(systemIsDark: false), .mint)
        XCTAssertEqual(preference.fixedSkin, .slate, "the one-skin choice is kept separately")
    }

    func testSavingAndLoadingRoundTrips() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var preference = SkinPreference()
        preference.mode = .fixed
        preference = preference.selecting(.turquoise)
        preference.dockIconFollowsSkin = false
        preference.save(to: defaults)
        XCTAssertEqual(SkinPreference.load(from: defaults), preference)
    }

    func testLoadingNothingGivesTheDefaults() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let loaded = SkinPreference.load(from: defaults)
        XCTAssertEqual(loaded, SkinPreference())
        XCTAssertEqual(loaded.mode, .followSystem)
        XCTAssertTrue(loaded.dockIconFollowsSkin)
    }

    func testBadSavedValuesFallBackToTheDefaults() {
        let (defaults, name) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("nonsense", forKey: SkinPreference.Keys.mode)
        defaults.set("nonsense", forKey: SkinPreference.Keys.fixed)
        defaults.set("mint", forKey: SkinPreference.Keys.dark)   // a light skin can't be the dark-mode skin
        defaults.set("slate", forKey: SkinPreference.Keys.light) // and the reverse
        let loaded = SkinPreference.load(from: defaults)
        XCTAssertEqual(loaded.mode, .followSystem)
        XCTAssertEqual(loaded.fixedSkin, .slate)
        XCTAssertEqual(loaded.darkSkin, .slate)
        XCTAssertEqual(loaded.lightSkin, .oyster)
    }

    func testSkinSettingsAreCopiedByTheOneTimeMove() {
        // Saved settings keep the QuickDropZone. prefix, so Quick Drop Zone's move can't leave them behind.
        XCTAssertTrue(SkinPreference.Keys.mode.hasPrefix(LegacyDataMigrationPolicy.appKeyPrefix))
    }
}
