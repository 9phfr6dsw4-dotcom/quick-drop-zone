import AppKit
import QuickDropZoneCore
import SwiftUI
import UniformTypeIdentifiers

/// The menu-bar panel: drop files, see what happened, open the window.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    dropZone
                    if let pending = model.pending {
                        PendingCard(pending: pending)
                    }
                    if let status = model.statusMessage {
                        Label(status, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let waiting = model.openSuggestions
                    if !waiting.isEmpty {
                        SectionLabel("Waiting for you (\(waiting.count))")
                        ForEach(waiting.prefix(3)) { entry in
                            ActivityRow(entry: entry, compact: true)
                        }
                    }
                    let recent = model.activity.filter { $0.kind != .suggested }.prefix(4)
                    if !recent.isEmpty {
                        HStack {
                            SectionLabel("Recent")
                            Spacer()
                            if model.lastMove != nil {
                                Button("Undo Last Move") { model.undoLastMove() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(QDZStyle.brass)
                            }
                        }
                        ForEach(Array(recent)) { entry in
                            ActivityRow(entry: entry, compact: true)
                        }
                    }
                    IntelligenceStatus()
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 400, height: 580)
        .background(WindowBackground().ignoresSafeArea())
        .qdzChrome()
        .alert("Quick Drop Zone", isPresented: Binding(
            get: { model.userError != nil },
            set: { if !$0 { model.userError = nil } }
        )) {
            Button("OK", role: .cancel) { model.userError = nil }
        } message: {
            Text(model.userError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
            Text("Quick Drop Zone")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Menu {
                Button("Clean Up Downloads…") {
                    model.startDownloadsCleanup()
                    MainWindowController.shared.show(.cleanup)
                }
                Button("Find a File…") { MainWindowController.shared.show(.find) }
                Divider()
                Button("Settings…") { MainWindowController.shared.show(.settings) }
                Button("Folders & Rules…") { MainWindowController.shared.show(.folders) }
                Divider()
                Button("Quit Quick Drop Zone") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                StatusItemController.shared.hidePanel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close (Esc). The panel stays open until you close it.")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// A recessed tray: dark inside, a brass dashed edge, and a glow when files are held over it.
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.black.opacity(isTargeted ? 0.18 : 0.4), Color.white.opacity(isTargeted ? 0.07 : 0.025)],
                    startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isTargeted ? QDZStyle.brass : QDZStyle.brass.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(QDZStyle.brass.opacity(isTargeted ? 0.26 : 0.1))
                    Circle()
                        .strokeBorder(QDZStyle.brass.opacity(0.55), lineWidth: 1)
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 21, weight: .light))
                        .foregroundStyle(QDZStyle.brass)
                }
                .frame(width: 54, height: 54)
                Text("Drop files here")
                    .font(.system(size: 15, weight: .semibold))
                Text(model.autoMove ? "Files it's sure about are filed right away, with Undo. The rest wait for you."
                     : "Nothing moves until you choose a folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 156)
        .scaleEffect(isTargeted ? 1.012 : 1)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: receiveDrop)
        .accessibilityLabel("Drop files to sort them")
    }

    /// One clear action: open the full window. Clean Up and Find are in the ⋯ menu.
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                MainWindowController.shared.show(.activity)
            } label: {
                Label("Open Quick Drop Zone", systemImage: "macwindow")
            }
            .buttonStyle(.brass)
            Spacer()
        }
        .padding(12)
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let collector = DropCollector(expected: fileProviders.count)
        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let value = item as? String {
                    url = URL(string: value)
                } else {
                    url = nil
                }
                Task { @MainActor in
                    if let urls = collector.add(url) { AppModel.shared.receiveDrops(urls) }
                }
            }
        }
        return true
    }
}

/// Collects the URLs of one multi-file drop, then hands them over together.
@MainActor
final class DropCollector {
    private let expected: Int
    private var received = 0
    private var urls: [URL] = []

    init(expected: Int) {
        self.expected = expected
    }

    func add(_ url: URL?) -> [URL]? {
        received += 1
        if let url { urls.append(url) }
        return received == expected ? urls : nil
    }
}

/// A dropped file waiting for a decision.
struct PendingCard: View {
    @Environment(AppModel.self) private var model
    let pending: PendingFile

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(pending.url.lastPathComponent, systemImage: "doc")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 6)
                Button { model.cancelPendingDrop() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
            if pending.isThinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Caption("Looking at this file…")
                }
            } else {
                if let reason = pending.reason {
                    let name = model.destinationName(for: pending.suggestionID)
                    Label(name.map { "Suggested: \($0) — \(reason)" } ?? reason, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let summary = pending.summary, !summary.isEmpty {
                    Caption(summary)
                }
                if let proposed = pending.proposedName {
                    Toggle("Rename to “\(proposed)”", isOn: $model.renamePendingFirst)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                if model.favoriteFolders.isEmpty {
                    Text("Add a favorite folder first (Folders & Rules).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    ForEach(model.favoriteFolders) { folder in
                        Button {
                            model.movePending(to: folder.id)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text("Move to \(folder.name)")
                                Spacer()
                                if folder.id == pending.suggestionID {
                                    Text("Suggested")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(QDZStyle.brass)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.pill)
                    }
                }
            }
        }
        .padding(12)
        .cardSurface(radius: 12)
    }
}
