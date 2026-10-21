import AppKit
import Observation
import QuickDropZoneCore
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension NSColor {
    convenience init(_ rgb: RGB) {
        self.init(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

/// The skin in use. Views read it while they draw (through `QDZStyle`), so they redraw by
/// themselves when the skin changes or when the Mac switches between light and dark.
///
/// By default Slate is used in dark mode and Oyster in light mode, following the Mac; or one chosen
/// skin is used whatever the Mac is set to. Skins change colours and the icon only.
@Observable
final class SkinStore {
    static let shared = SkinStore()

    private(set) var preference: SkinPreference
    private(set) var systemIsDark: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var iconCache: [Skin: NSImage] = [:]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = SkinPreference.load(from: defaults)
        // The global setting is "Dark" in dark mode and missing in light mode.
        systemIsDark = defaults.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// The skin to draw right now.
    var skin: Skin { preference.resolved(systemIsDark: systemIsDark) }
    var palette: SkinPalette { skin.palette }

    // MARK: Settings page

    /// Whether this skin is the one (or one of the two) in use, for the highlight in Settings.
    func isChosen(_ candidate: Skin) -> Bool {
        switch preference.mode {
        case .fixed: return candidate == preference.fixedSkin
        case .followSystem: return candidate == preference.darkSkin || candidate == preference.lightSkin
        }
    }

    /// "Dark mode", "Light mode" or "Selected" on the tile of a skin in use.
    func badge(for candidate: Skin) -> String? {
        switch preference.mode {
        case .fixed:
            return candidate == preference.fixedSkin ? "Selected" : nil
        case .followSystem:
            if candidate == preference.darkSkin { return "Dark mode" }
            if candidate == preference.lightSkin { return "Light mode" }
            return nil
        }
    }

    // MARK: Changing the skin

    @MainActor
    func setMode(_ mode: SkinMode) {
        var next = preference
        next.mode = mode
        update(next)
    }

    @MainActor
    func select(_ skin: Skin) {
        update(preference.selecting(skin))
    }

    @MainActor
    func setDockIconFollowsSkin(_ follows: Bool) {
        var next = preference
        next.dockIconFollowsSkin = follows
        update(next)
    }

    @MainActor
    private func update(_ next: SkinPreference) {
        guard next != preference else { return }
        preference = next
        next.save(to: defaults)
        skinChanged()
    }

    // MARK: Following the Mac

    /// Starts watching the Mac's light and dark setting and applies the skin to the windows and the Dock.
    @MainActor
    func start() {
        guard observers.isEmpty else { return }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            // The system's own appearance value settles a moment after the notification.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                self?.refreshSystemAppearance()
            }
        })
        // A second check whenever the app comes to the front, in case a change was missed.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshSystemAppearance() }
        })
        refreshSystemAppearance()
        skinChanged()
    }

    @MainActor
    private func refreshSystemAppearance() {
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let dark = match == .darkAqua
        guard dark != systemIsDark else { return }
        systemIsDark = dark
        skinChanged()
    }

    // MARK: Applying it outside SwiftUI

    @MainActor
    private func skinChanged() {
        applyToWindows()
        applyAppIcon()
    }

    /// Every titled window and the panel follows the skin's light or dark appearance.
    @MainActor
    func applyToWindows() {
        let appearance = NSAppearance(named: skin.isDark ? .darkAqua : .aqua)
        for window in NSApplication.shared.windows where window is NSPanel || window.styleMask.contains(.titled) {
            window.appearance = appearance
            window.backgroundColor = QDZStyle.windowBackgroundNS
        }
    }

    /// The Dock icon and the icon on the app in Finder for the skin in use. Oyster, the default,
    /// is the app's own icon.
    @MainActor
    func applyAppIcon() {
        let iconSkin = preference.dockIconFollowsSkin && skin != .oyster ? skin : nil
        if let iconSkin, let image = bundledIcon(for: iconSkin) {
            NSApplication.shared.applicationIconImage = image
        } else {
            NSApplication.shared.applicationIconImage = nil
        }
        FinderIcon.show(iconSkin)
    }

    /// The icon drawn for a skin (bundled in Resources/SkinIcons), or nil if it isn't there.
    @MainActor
    func bundledIcon(for skin: Skin) -> NSImage? {
        if let cached = iconCache[skin] { return cached }
        guard let url = Bundle.main.url(forResource: "icon-\(skin.rawValue)", withExtension: "png", subdirectory: "SkinIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        iconCache[skin] = image
        return image
    }

    /// The icon for a skin, or the app's own icon if it isn't bundled (for the sidebar and the panel).
    @MainActor
    func iconImage(for skin: Skin) -> NSImage {
        bundledIcon(for: skin) ?? NSApplication.shared.applicationIconImage
    }
}
