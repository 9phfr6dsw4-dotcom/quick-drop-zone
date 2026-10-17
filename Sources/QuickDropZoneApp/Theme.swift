import AppKit
import QuickDropZoneCore
import SwiftUI

/// Graphite surfaces with thin champagne-brass details, matching the app icon. The app is always dark.
enum QDZStyle {
    static let brass = Color(red: 0.84, green: 0.72, blue: 0.47)
    static let brassLight = Color(red: 0.95, green: 0.87, blue: 0.66)
    static let brassDeep = Color(red: 0.62, green: 0.48, blue: 0.26)
    static let hairline = Color.white.opacity(0.09)
    static let cardFill = Color.white.opacity(0.045)
    static let windowBackgroundNS = NSColor(calibratedRed: 0.075, green: 0.080, blue: 0.092, alpha: 1)
}

/// Graphite with a faint warm glow in the top-left corner, like light on brushed metal.
struct WindowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.108, green: 0.113, blue: 0.128), Color(red: 0.060, green: 0.064, blue: 0.074)],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [QDZStyle.brass.opacity(0.07), Color.clear], center: .topLeading, startRadius: 0, endRadius: 560)
        }
    }
}

/// The surface of every card: lit from above, with a fine edge and a soft shadow.
struct CardSurface: ViewModifier {
    var radius: CGFloat
    var hovering: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(hovering ? 0.088 : 0.066), Color.white.opacity(hovering ? 0.052 : 0.03)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(0.17), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
    }
}

extension View {
    func cardSurface(radius: CGFloat = 14, hovering: Bool = false) -> some View {
        modifier(CardSurface(radius: radius, hovering: hovering))
    }
}

/// A row of fine ruler ticks in brass, echoing the dial on the app icon.
struct TickRule: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            var index = 0
            while x < size.width {
                let major = index % 5 == 0
                let fade = max(0.0, 1.0 - Double(x / size.width))
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x, y: size.height - (major ? 9 : 5)))
                context.stroke(path, with: .color(QDZStyle.brass.opacity((major ? 0.75 : 0.4) * fade)), lineWidth: major ? 1.2 : 0.8)
                x += 6
                index += 1
            }
        }
        .frame(width: 168, height: 10)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Dark appearance, brass tint and card-style group boxes for everything inside.
    func qdzChrome() -> some View {
        self
            .tint(QDZStyle.brass)
            .groupBoxStyle(CardGroupBoxStyle())
            .preferredColorScheme(.dark)
    }
}

/// Every `GroupBox` in the app: a soft card with a thin edge and a small brass heading.
struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(QDZStyle.brass)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// A card without a heading.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

/// Small rounded buttons (Undo, Rename, Show in Finder).
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.white.opacity(configuration.isPressed ? 0.17 : 0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(QDZStyle.hairline, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// The main action: a brass pill with dark text.
struct BrassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.03))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                LinearGradient(colors: [QDZStyle.brassLight, QDZStyle.brass], startPoint: .top, endPoint: .bottom),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75))
            .shadow(color: QDZStyle.brass.opacity(0.25), radius: 6, y: 2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
}

extension ButtonStyle where Self == BrassButtonStyle {
    static var brass: BrassButtonStyle { BrassButtonStyle() }
}

/// A small tag, like the folder a file went to.
struct Chip: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(highlighted ? QDZStyle.brass : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(highlighted ? QDZStyle.brass.opacity(0.14) : Color.white.opacity(0.08), in: Capsule())
            .lineLimit(1)
    }
}

/// A small uppercase brass heading for a block of the panel.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(QDZStyle.brass)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.4)
            TickRule()
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A scrolling page: large title, subtitle, content, privacy footer.
struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: title, subtitle: subtitle)
                content()
                PrivacyFooter()
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(WindowBackground().ignoresSafeArea())
    }
}

struct PrivacyFooter: View {
    var body: some View {
        Label("Your files are read and sorted on this Mac only. Nothing is uploaded, and nothing is ever deleted.", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shows Apple Intelligence's state in one line.
struct IntelligenceStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let reason = model.aiUnavailableReason {
            Label(reason, systemImage: "sparkles.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Apple Intelligence is on, running on this Mac only.", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(QDZStyle.brass)
        }
    }
}

enum TimeText {
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// One entry in Activity: what happened, where it went, why, and Undo / Rename / Move buttons.
struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false
    let entry: ActivityEntry
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                leadingIcon
                if compact {
                    compactHeader
                } else {
                    fullHeader
                }
                Spacer(minLength: 6)
                Text(TimeText.relative(entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !compact {
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !compact, let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
                .padding(.leading, 32)
                .buttonStyle(.pill)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 13, hovering: hovering)
        .opacity(entry.isUndone ? 0.6 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// The file's own Finder icon, with a small brass spark on files filed automatically.
    private var leadingIcon: some View {
        let fileIcon = NSWorkspace.shared.icon(forFile: entry.filePath)
        return Image(nsImage: fileIcon)
            .resizable()
            .interpolation(.high)
            .frame(width: 22, height: 22)
            .overlay(alignment: .bottomTrailing) {
                if entry.kind == .autoMoved {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(QDZStyle.brass)
                        .padding(2)
                        .background(Circle().fill(Color.black.opacity(0.75)))
                        .offset(x: 4, y: 4)
                }
            }
            .opacity(entry.isUndone ? 0.5 : 1)
            .accessibilityHidden(true)
    }

    /// The panel is narrow: one line, with the destination in the text.
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The window has room: the file name, then tags for where it went and whether it was automatic.
    private var fullHeader: some View {
        HStack(spacing: 8) {
            Text(fullTitle)
                .font(.system(size: 13.5, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
            if entry.kind == .moved || entry.kind == .autoMoved, let name = entry.destinationName {
                Chip(text: name)
            }
            if entry.kind == .autoMoved {
                Chip(text: "Automatic", highlighted: true)
            }
        }
    }

    private var symbol: String {
        switch entry.kind {
        case .autoMoved: return "sparkles"
        case .moved: return "folder.fill"
        case .renamed: return "pencil"
        case .suggested: return "questionmark.folder"
        }
    }

    private var tint: Color {
        entry.kind == .suggested ? Color.orange : QDZStyle.brass
    }

    private var fullTitle: String {
        switch entry.kind {
        case .autoMoved, .moved, .renamed: return entry.fileName
        case .suggested:
            return entry.destinationName.map { "\(entry.fileName): move to \($0)?" } ?? "\(entry.fileName): a clearer name?"
        }
    }

    private var title: String {
        switch entry.kind {
        case .autoMoved: return "\(entry.fileName) → \(entry.destinationName ?? "folder") (automatic)"
        case .moved: return "\(entry.fileName) → \(entry.destinationName ?? "folder")"
        case .renamed: return entry.fileName
        case .suggested:
            return entry.destinationName.map { "\(entry.fileName): move to \($0)?" } ?? "\(entry.fileName): a clearer name?"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            if entry.isUndone {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else if entry.kind == .suggested {
                if let name = entry.destinationName {
                    Button("Move to \(name)") { model.acceptSuggestion(entry.id) }
                        .buttonStyle(.brass)
                }
                if !model.favoriteFolders.isEmpty {
                    Menu("Other Folder") {
                        ForEach(model.favoriteFolders) { folder in
                            Button(folder.name) { model.acceptSuggestion(entry.id, destinationID: folder.id) }
                        }
                    }
                    .fixedSize()
                }
                if let proposed = entry.proposedName {
                    Button("Rename to “\(proposed)”") { model.applyProposedName(entry.id) }
                }
                Button("Dismiss") { model.dismiss(entry.id) }
            } else {
                if entry.receipt != nil {
                    Button("Undo") { model.undo(entry.id) }
                }
                if let proposed = entry.proposedName {
                    Button("Rename to “\(proposed)”") { model.applyProposedName(entry.id) }
                }
                if entry.kind != .renamed {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.filePath)])
                    }
                }
            }
        }
    }
}

/// A Settings row: the label on the left, a switch on the right.
struct SettingToggle: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }
}
