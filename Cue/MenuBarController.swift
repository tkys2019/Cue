import SwiftUI
import AppKit

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let panel: NSPanel
    
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var commandIsDown = false
    private var commandWasUsed = false
    private var lastCommandTapTime: TimeInterval = 0

    private let doubleCommandInterval: TimeInterval = 0.35

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
        
        startCommandMonitor()
    }
    
    @objc private func statusItemClicked() {
        toggleCue()
    }
    
    private func toggleCue() {
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
    
    private func startCommandMonitor() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleKeyboardEvent(event)
            return event
        }
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        switch event.type {

        case .keyDown:
            if event.isARepeat {
                return
            }

            if commandIsDown {
                commandWasUsed = true
            }

            lastCommandTapTime = 0

        case .flagsChanged:
            let commandDownNow = event.modifierFlags.contains(.command)

            if commandDownNow && !commandIsDown {
                // ⌘を押した
                commandIsDown = true
                commandWasUsed = false

            } else if !commandDownNow && commandIsDown {
                // ⌘を離した
                commandIsDown = false

                if commandWasUsed {
                    lastCommandTapTime = 0
                    return
                }

                let now = event.timestamp

                if lastCommandTapTime > 0,
                   now - lastCommandTapTime <= doubleCommandInterval {

                    lastCommandTapTime = 0
                    toggleCue()

                } else {
                    lastCommandTapTime = now
                }

            } else if commandIsDown {
                // ⌘を押している最中にShift等が触られた
                commandWasUsed = true
            }

        default:
            break
        }
    }
    
    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
