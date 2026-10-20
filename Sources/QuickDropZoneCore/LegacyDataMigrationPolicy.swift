import Foundation

/// The one-time move of Quick Drop Zone's saved settings into Levant (the app was renamed in 2.6.0
/// with a new bundle ID, so macOS gives it a fresh settings domain).
///
/// Only Quick Drop Zone's own keys come across (favorite folders and their notes, rules, learned
/// patterns, activity, watched folders and the switches), plus Sparkle's two user choices. Sparkle's
/// other keys are the old app's update history and stay behind. Anything Levant has already saved
/// itself is never overwritten.
public enum LegacyDataMigrationPolicy {
    /// The old app's bundle ID, and so the name of its settings domain.
    public static let legacyBundleIdentifier = "com.quickdropzone.app"
    /// Set in Levant's settings once everything has been moved, so it never looks again.
    public static let doneKey = "Levant.importedQuickDropZoneData"

    static let appKeyPrefix = "QuickDropZone."
    static let sparkleUserChoices: Set<String> = ["SUEnableAutomaticChecks", "SUAutomaticallyUpdate"]
    /// Written only by CI's update test.
    static let testOnlyKeys: Set<String> = ["QuickDropZone.updateTestMarker"]

    /// The keys to copy, in a stable order.
    public static func keysToCopy(legacy: [String: Any], existing: Set<String>) -> [String] {
        legacy.keys
            .filter { key in
                if existing.contains(key) { return false }
                if testOnlyKeys.contains(key) { return false }
                return key.hasPrefix(appKeyPrefix) || sparkleUserChoices.contains(key)
            }
            .sorted()
    }

    /// Copies the settings across and marks the move as done. Returns how many keys were copied.
    @discardableResult
    public static func migrate(legacy: [String: Any], into defaults: UserDefaults) -> Int {
        let existing = Set(defaults.dictionaryRepresentation().keys)
        let keys = keysToCopy(legacy: legacy, existing: existing)
        for key in keys {
            defaults.set(legacy[key], forKey: key)
        }
        defaults.set(true, forKey: doneKey)
        return keys.count
    }
}
