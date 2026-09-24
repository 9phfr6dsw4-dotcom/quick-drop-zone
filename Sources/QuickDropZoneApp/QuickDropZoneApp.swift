import AppKit
import SwiftUI

@main
struct QuickDropZoneApp: App {
    @NSApplicationDelegateAdaptor(StatusBarDelegate.self) private var statusBarDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
private final class StatusBarDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Quick Drop Zone")
            button.toolTip = "Quick Drop Zone"
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 590)
        popover.contentViewController = NSHostingController(
            rootView: MainPopoverView().environmentObject(AppModel.shared)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
