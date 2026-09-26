import SwiftUI
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        registerLoginItemIfNeeded()
    }

    private func registerLoginItemIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
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
