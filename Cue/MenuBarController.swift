import SwiftUI
import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let panel: NSPanel

    override init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        
        let hostingController = NSHostingController(
            rootView: ContentView()
                .frame(width: 360, height: 300)
        )

        hostingController.sizingOptions = []

        panel.contentViewController = hostingController
        panel.setContentSize(NSSize(width: 360, height: 300))

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary
        ]

        panel.isReleasedWhenClosed = false

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "lightbulb",
                accessibilityDescription: "Cue"
            )

            button.target = self
            button.action = #selector(statusItemClicked)
        }
    }
    
    @objc private func statusItemClicked() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showCue()
        }
    }
    
    private func showCue() {
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
    }
}
