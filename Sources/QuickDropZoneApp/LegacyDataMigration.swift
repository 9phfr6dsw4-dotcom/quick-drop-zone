import AppKit
import QuickDropZoneCore

/// Brings Quick Drop Zone's settings into Levant the first time Levant opens. Runs before
/// anything reads a setting. Nothing is deleted from the old app's settings.
enum LegacyDataMigration {
    private static let legacyID = LegacyDataMigrationPolicy.legacyBundleIdentifier

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: LegacyDataMigrationPolicy.doneKey) else { return }

        // A running Quick Drop Zone would keep rewriting its own settings, so ask it to quit first.
        // If it won't, leave everything alone and try again next launch.
        if !quitLegacyApp() { return }

        let legacy = defaults.persistentDomain(forName: legacyID) ?? [:]
        LegacyDataMigrationPolicy.migrate(legacy: legacy, into: defaults)
    }

    /// True once no Quick Drop Zone is running (waits up to 5 seconds).
    private static func quitLegacyApp() -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: legacyID)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: legacyID).isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: legacyID).isEmpty
    }
}
