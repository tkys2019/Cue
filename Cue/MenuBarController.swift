import SwiftUI
import AppKit
import ServiceManagement

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let panel: NSPanel
    private var defaultsObserver: NSObjectProtocol?
    
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
        
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        
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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        applyBackground()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyBackground()
        }

        startCommandMonitor()
    }
    
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        toggleCue()
    }

    private func showStatusMenu() {
        let defaults = UserDefaults.standard
        let menu = NSMenu()

        menu.addItem(.sectionHeader(title: "Appearance"))
        let timestampsItem = menuItem("Show timestamps", action: #selector(toggleTimestamps))
        timestampsItem.state = defaults.bool(forKey: "showTimestamps") ? .on : .off
        menu.addItem(timestampsItem)

        let background = defaults.string(forKey: "background")
            .flatMap(CueBackground.init(rawValue:)) ?? .system
        let backgroundMenu = NSMenu()
        for option in CueBackground.allCases {
            let item = menuItem(option.title, action: #selector(selectBackground(_:)))
            item.representedObject = option.rawValue
            item.state = option == background ? .on : .off
            backgroundMenu.addItem(item)
        }
        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        backgroundItem.submenu = backgroundMenu
        menu.addItem(backgroundItem)

        let transparency = defaults.object(forKey: "transparency") as? Double ?? 0.9
        let transparencyMenu = NSMenu()
        for percent in stride(from: 60, through: 100, by: 5) {
            let item = menuItem("\(percent)%", action: #selector(selectTransparency(_:)))
            item.tag = percent
            item.state = Int((transparency * 100).rounded()) == percent ? .on : .off
            transparencyMenu.addItem(item)
        }
        let transparencyItem = NSMenuItem(title: "Transparency", action: nil, keyEquivalent: "")
        transparencyItem.submenu = transparencyMenu
        menu.addItem(transparencyItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Quick Launch"))
        let loginItem = menuItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        // Reflect the actual login item state, not only the saved setting.
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        // No action: shown as a disabled, display-only item.
        menu.addItem(NSMenuItem(title: "Keyboard Shortcut: ⌘⌘", action: nil, keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "About"))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        menu.addItem(NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(menuItem("GitHub", action: #selector(openGitHub)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Cue",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        ))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleTimestamps() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "showTimestamps"), forKey: "showTimestamps")
    }

    @objc private func selectBackground(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: "background")
    }

    @objc private func selectTransparency(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag) / 100, forKey: "transparency")
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Cue: failed to update login item: \(error)")
        }
        // Save the resulting state, so a failed attempt is not stored as success
        // and a successful OFF is not re-registered at next launch.
        UserDefaults.standard.set(service.status != .notRegistered, forKey: "launchAtLogin")
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/tkys2019/Cue")!)
    }

    private func applyBackground() {
        let background = UserDefaults.standard.string(forKey: "background")
            .flatMap(CueBackground.init(rawValue:)) ?? .system
        let appearance: NSAppearance? = switch background {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if panel.appearance?.name != appearance?.name {
            panel.appearance = appearance
        }
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
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
