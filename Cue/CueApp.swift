import SwiftUI
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: CuePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = CuePanelController()
        registerLoginItemIfNeeded()
    }

    // Opening Cue again (Spotlight, Finder, etc.) shows the panel,
    // as a fallback entry point besides ⌘⌘.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.showCue()
        return false
    }

    private func registerLoginItemIfNeeded() {
        // Defaults to ON. Turning it OFF is left to System Settings > Login Items.
        // A previously saved OFF (from the old menu bar menu) is still respected.
        let enabled = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true
        let service = SMAppService.mainApp
        guard enabled, service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            print("Cue: failed to register login item: \(error)")
        }
    }
}

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
