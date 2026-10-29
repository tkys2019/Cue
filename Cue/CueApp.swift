import SwiftUI
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: CuePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = CuePanelController()
        askLaunchAtLoginIfNeeded()
    }

    // Opening Cue again (Spotlight, Finder, etc.) shows the panel,
    // as a fallback entry point besides ⌘⌘.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.showCue()
        return false
    }

    // Asks once on first launch. Turning it OFF later is left to System Settings > Login Items.
    // A saved answer (including OFF from the old menu bar menu) is respected.
    private func askLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "launchAtLogin") == nil else { return }
        let service = SMAppService.mainApp
        if service.status == .enabled {
            defaults.set(true, forKey: "launchAtLogin")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Launch Cue at login?"
        alert.informativeText = "Cue runs in the background and opens with ⌘⌘. You can change this later in System Settings > General > Login Items."
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        let enable = alert.runModal() == .alertFirstButtonReturn
        defaults.set(enable, forKey: "launchAtLogin")
        guard enable else { return }
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
