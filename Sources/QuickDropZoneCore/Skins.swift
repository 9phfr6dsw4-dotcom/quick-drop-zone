import Foundation

/// A colour as plain numbers (0 to 1), so the palettes can be tested without any UI framework.
public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `RGB(hex: 0xA9C2DA)`.
    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1 to 21).
    public static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let a = first.relativeLuminance
        let b = second.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The colours a skin gives the app. Everything else (text, secondary text) follows the light or
/// dark appearance the skin asks for.
public struct SkinPalette: Equatable, Sendable {
    /// The top of the window background.
    public let background: RGB
    /// The bottom of the window background.
    public let backgroundDeep: RGB
    public let sidebar: RGB
    /// The accent used for the thin details, the heading labels and the main button.
    public let accent: RGB
    /// The top of the main button's gradient.
    public let accentLight: RGB
    public let accentDeep: RGB
    /// Text on the main button.
    public let onAccent: RGB
    /// The two ends of the icon's steel bezel, used by the Settings previews.
    public let bezelLight: RGB
    public let bezelDark: RGB
}

/// A colour scheme for the whole app. Skins change colours and the icon only.
public enum Skin: String, CaseIterable, Sendable {
    case slate, oyster, sky, submariner, turquoise, bordeaux, wisteria, mint

    public static let defaultDark: Skin = .slate
    public static let defaultLight: Skin = .oyster

    public var displayName: String {
        switch self {
        case .slate: return "Slate"
        case .oyster: return "Oyster"
        case .sky: return "Sky"
        case .submariner: return "Submariner"
        case .turquoise: return "Turquoise"
        case .bordeaux: return "Bordeaux"
        case .wisteria: return "Wisteria"
        case .mint: return "Mint"
        }
    }

    public var tagline: String {
        switch self {
        case .slate: return "Default, dark"
        case .oyster: return "Default, light"
        case .sky: return "Midnight blue"
        case .submariner: return "Deep green"
        case .turquoise: return "Deep teal"
        case .bordeaux: return "Wine red"
        case .wisteria: return "Soft violet"
        case .mint: return "Light, green"
        }
    }

    /// Light skins use the light appearance; the rest use the dark one.
    public var isDark: Bool {
        switch self {
        case .oyster, .mint: return false
        default: return true
        }
    }

    public var palette: SkinPalette {
        switch self {
        case .slate:
            return SkinPalette(
                background: RGB(hex: 0x22262B), backgroundDeep: RGB(hex: 0x1A1D21), sidebar: RGB(hex: 0x1A1D21),
                accent: RGB(hex: 0xA9C2DA), accentLight: RGB(hex: 0xC6D8EA), accentDeep: RGB(hex: 0x6F8CA8),
                onAccent: RGB(hex: 0x0E1620), bezelLight: RGB(hex: 0xF4F6F8), bezelDark: RGB(hex: 0x7D8792))
        case .oyster:
            return SkinPalette(
                background: RGB(hex: 0xF6F4EF), backgroundDeep: RGB(hex: 0xECE9E2), sidebar: RGB(hex: 0xECE9E2),
                accent: RGB(hex: 0x2B5784), accentLight: RGB(hex: 0x3E6C9C), accentDeep: RGB(hex: 0x1F3F63),
                onAccent: RGB(hex: 0xFFFFFF), bezelLight: RGB(hex: 0xF7F8F9), bezelDark: RGB(hex: 0x98A0AA))
        case .sky:
            return SkinPalette(
                background: RGB(hex: 0x0B1424), backgroundDeep: RGB(hex: 0x08101D), sidebar: RGB(hex: 0x08101D),
                accent: RGB(hex: 0x86B5F4), accentLight: RGB(hex: 0xA9CBF7), accentDeep: RGB(hex: 0x4C7FC4),
                onAccent: RGB(hex: 0x06142B), bezelLight: RGB(hex: 0xDDE8FA), bezelDark: RGB(hex: 0x7592BE))
        case .submariner:
            return SkinPalette(
                background: RGB(hex: 0x0D100E), backgroundDeep: RGB(hex: 0x090B0A), sidebar: RGB(hex: 0x090B0A),
                accent: RGB(hex: 0x4FCB8A), accentLight: RGB(hex: 0x7BDDA8), accentDeep: RGB(hex: 0x2A7A52),
                onAccent: RGB(hex: 0x04140A), bezelLight: RGB(hex: 0x4A504C), bezelDark: RGB(hex: 0x131614))
        case .turquoise:
            return SkinPalette(
                background: RGB(hex: 0x0C1B1D), backgroundDeep: RGB(hex: 0x081416), sidebar: RGB(hex: 0x081416),
                accent: RGB(hex: 0x5FD0C8), accentLight: RGB(hex: 0x8EE3DC), accentDeep: RGB(hex: 0x2F8F89),
                onAccent: RGB(hex: 0x04201F), bezelLight: RGB(hex: 0xCFF3EF), bezelDark: RGB(hex: 0x3E8F8A))
        case .bordeaux:
            return SkinPalette(
                background: RGB(hex: 0x1D1013), backgroundDeep: RGB(hex: 0x160B0E), sidebar: RGB(hex: 0x160B0E),
                accent: RGB(hex: 0xE8909F), accentLight: RGB(hex: 0xF2B3BE), accentDeep: RGB(hex: 0xA33B4F),
                onAccent: RGB(hex: 0x2A0A10), bezelLight: RGB(hex: 0xF0C5CC), bezelDark: RGB(hex: 0xA33B4F))
        case .wisteria:
            return SkinPalette(
                background: RGB(hex: 0x171424), backgroundDeep: RGB(hex: 0x110F1D), sidebar: RGB(hex: 0x110F1D),
                accent: RGB(hex: 0xB9A6F2), accentLight: RGB(hex: 0xD3C6F7), accentDeep: RGB(hex: 0x7D6BC0),
                onAccent: RGB(hex: 0x130C2E), bezelLight: RGB(hex: 0xE3DAFA), bezelDark: RGB(hex: 0x7D6BC0))
        case .mint:
            return SkinPalette(
                background: RGB(hex: 0xF2F6F3), backgroundDeep: RGB(hex: 0xE6EEE9), sidebar: RGB(hex: 0xE6EEE9),
                accent: RGB(hex: 0x1E6B4A), accentLight: RGB(hex: 0x2D7F5C), accentDeep: RGB(hex: 0x17503A),
                onAccent: RGB(hex: 0xFFFFFF), bezelLight: RGB(hex: 0xF4FAF6), bezelDark: RGB(hex: 0x8FA89B))
        }
    }
}

/// Follow the Mac's light or dark setting, or always use one skin.
public enum SkinMode: String, CaseIterable, Sendable {
    case followSystem
    case fixed
}

/// Which skin is used. By default Slate in dark mode and Oyster in light mode, following the Mac;
/// or one chosen skin that ignores the Mac's setting.
public struct SkinPreference: Equatable, Sendable {
    public var mode: SkinMode
    public var darkSkin: Skin
    public var lightSkin: Skin
    public var fixedSkin: Skin
    /// Whether the Dock icon and the icon on the app in Finder follow the skin (the saved key keeps
    /// its 2.7.0 name).
    public var dockIconFollowsSkin: Bool

    public init(mode: SkinMode = .followSystem, darkSkin: Skin = .defaultDark, lightSkin: Skin = .defaultLight,
                fixedSkin: Skin = .defaultDark, dockIconFollowsSkin: Bool = true) {
        self.mode = mode
        self.darkSkin = darkSkin
        self.lightSkin = lightSkin
        self.fixedSkin = fixedSkin
        self.dockIconFollowsSkin = dockIconFollowsSkin
    }

    /// The skin to show right now.
    public func resolved(systemIsDark: Bool) -> Skin {
        switch mode {
        case .fixed: return fixedSkin
        case .followSystem: return systemIsDark ? darkSkin : lightSkin
        }
    }

    /// Picking a skin: while following the Mac it becomes the skin for its own kind of mode (a dark
    /// skin for dark mode, a light skin for light mode); otherwise it becomes the one skin used.
    public func selecting(_ skin: Skin) -> SkinPreference {
        var copy = self
        switch mode {
        case .fixed: copy.fixedSkin = skin
        case .followSystem:
            if skin.isDark { copy.darkSkin = skin } else { copy.lightSkin = skin }
        }
        return copy
    }

    // MARK: Saving

    enum Keys {
        static let mode = "QuickDropZone.appearance.mode.v1"
        static let dark = "QuickDropZone.appearance.darkSkin.v1"
        static let light = "QuickDropZone.appearance.lightSkin.v1"
        static let fixed = "QuickDropZone.appearance.fixedSkin.v1"
        static let dock = "QuickDropZone.appearance.dockIconFollowsSkin.v1"
    }

    /// Unknown or missing values fall back to the defaults, and a dark-mode skin is never a light one.
    public static func load(from defaults: UserDefaults) -> SkinPreference {
        func skin(_ key: String) -> Skin? {
            defaults.string(forKey: key).flatMap(Skin.init(rawValue:))
        }
        var preference = SkinPreference()
        if let raw = defaults.string(forKey: Keys.mode), let mode = SkinMode(rawValue: raw) { preference.mode = mode }
        if let dark = skin(Keys.dark), dark.isDark { preference.darkSkin = dark }
        if let light = skin(Keys.light), !light.isDark { preference.lightSkin = light }
        if let fixed = skin(Keys.fixed) { preference.fixedSkin = fixed }
        preference.dockIconFollowsSkin = defaults.object(forKey: Keys.dock) as? Bool ?? true
        return preference
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(darkSkin.rawValue, forKey: Keys.dark)
        defaults.set(lightSkin.rawValue, forKey: Keys.light)
        defaults.set(fixedSkin.rawValue, forKey: Keys.fixed)
        defaults.set(dockIconFollowsSkin, forKey: Keys.dock)
    }
}
