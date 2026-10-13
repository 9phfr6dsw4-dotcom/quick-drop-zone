import AppKit
import QuickDropZoneCore
import SwiftUI

/// The same look as EchoFlow, EchoLedger and Lumen.
enum QDZStyle {
    static let blue = Color(red: 0.17, green: 0.49, blue: 0.94)
    static let cyan = Color(red: 0.55, green: 0.88, blue: 1.0)
    static let green = Color(red: 0.16, green: 0.62, blue: 0.40)
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.title3)
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
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                .foregroundStyle(QDZStyle.blue)
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

/// One line in Activity: what happened, why, and Undo / Rename / Move buttons.
struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    let entry: ActivityEntry
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(entry.isUndone ? Color.secondary : tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(compact ? 1 : 2)
                        .truncationMode(.middle)
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 3)
                }
                Spacer(minLength: 6)
                Text(TimeText.relative(entry.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !compact, let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
                .padding(.leading, 26)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .opacity(entry.isUndone ? 0.6 : 1)
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
        entry.kind == .suggested ? Color.orange : QDZStyle.blue
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
                        .buttonStyle(.borderedProminent)
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
