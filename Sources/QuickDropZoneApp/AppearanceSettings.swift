import AppKit
import QuickDropZoneCore
import SwiftUI

/// Settings > Appearance: follow the Mac's light and dark setting, or always use one skin.
struct AppearanceSettings: View {
    var body: some View {
        let store = SkinStore.shared
        let following = store.preference.mode == .followSystem
        GroupBox("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Skins", selection: Binding(
                    get: { store.preference.mode },
                    set: { store.setMode($0) }
                )) {
                    Text("Follow my Mac").tag(SkinMode.followSystem)
                    Text("Choose one skin").tag(SkinMode.fixed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
                Caption(following
                    ? "Your Mac decides: Slate in dark mode and Oyster in light mode, unless you pick others below. A dark skin you pick is used in dark mode, a light one in light mode."
                    : "Always uses the skin you pick, whatever your Mac is set to.")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(Skin.allCases, id: \.self) { skin in
                        SkinTile(skin: skin)
                    }
                }
                SettingToggle("Dock icon follows the skin", isOn: Binding(
                    get: { store.preference.dockIconFollowsSkin },
                    set: { store.setDockIconFollowsSkin($0) }
                ))
                Caption("Skins change colors and the icon only. How files are filed never changes.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

/// One skin in the Settings grid: a tiny preview of the window in its colours, its name, and whether it's in use.
struct SkinTile: View {
    let skin: Skin

    var body: some View {
        let store = SkinStore.shared
        let chosen = store.isChosen(skin)
        Button {
            store.select(skin)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                preview
                VStack(alignment: .leading, spacing: 1) {
                    Text(skin.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(store.badge(for: skin) ?? skin.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(chosen ? QDZStyle.brass : Color.secondary)
                        .lineLimit(1)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(QDZStyle.wash(0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(chosen ? QDZStyle.brass : QDZStyle.hairline, lineWidth: chosen ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skin.displayName), \(skin.tagline)")
        .accessibilityAddTraits(chosen ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// A miniature window: sidebar, a title line, a body line, an accent button and a dial.
    private var preview: some View {
        let palette = skin.palette
        let text = skin.isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.8)
        return ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(palette.sidebar))
                    .frame(width: 26)
                ZStack(alignment: .topLeading) {
                    Color(palette.background)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(text).frame(width: 34, height: 4)
                        Capsule().fill(text.opacity(0.4)).frame(width: 52, height: 3)
                        Capsule().fill(Color(palette.accent)).frame(width: 24, height: 6)
                    }
                    .padding(8)
                }
            }
            Circle()
                .fill(LinearGradient(colors: [Color(palette.bezelLight), Color(palette.bezelDark)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
                .overlay(Circle().fill(Color(palette.background)).padding(4))
                .padding(5)
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.gray.opacity(0.3), lineWidth: 1))
    }
}

/// The Apple Intelligence mark in the sidebar card: the artwork bundled as IntelligenceMark.png (a light rounded
/// tile with seven interlaced loops). If the file is missing (a build run outside the packaged app), a drawn
/// version of the loops is used instead.
struct IntelligenceMark: View {
    var available = true

    private static let artwork: NSImage? = Bundle.main.url(forResource: "IntelligenceMark", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let artwork = Self.artwork {
                // The artwork has a little space and shadow around its tile; this keeps the tile at 34 points.
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .padding(-3)
            } else {
                drawn
            }
        }
        .frame(width: 34, height: 34)
        .saturation(available ? 1 : 0)
        .opacity(available ? 1 : 0.5)
        .accessibilityHidden(true)
    }

    private var drawn: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(red: 0.90, green: 0.91, blue: 0.92)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
            LinearGradient(
                colors: [Color(red: 0.165, green: 0.227, blue: 0.341), Color(red: 0.345, green: 0.380, blue: 0.478), Color(red: 0.78, green: 0.71, blue: 0.49)],
                startPoint: .top, endPoint: .bottom)
                .mask { rosette }
                .padding(4)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1)
    }

    /// Seven ellipses turned round the centre, so each crosses its neighbours and the middle stays open.
    private var rosette: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<7, id: \.self) { index in
                    ZStack {
                        Ellipse()
                            .stroke(Color.black, lineWidth: side * 0.06)
                            .frame(width: side * 0.59, height: side * 0.22)
                            .offset(y: -side * 0.25)
                    }
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(Double(index) * 360.0 / 7.0))
                }
            }
            .frame(width: side, height: side)
        }
    }
}
