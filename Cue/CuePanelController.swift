import SwiftUI
import AppKit
import Carbon

final class CuePanelController: NSObject {
    private let panel: NSPanel
    private var defaultsObserver: NSObjectProtocol?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let keyRouter = CueKeyRouter()
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyIsDown = false
    private var configuredTrigger: CueKeyBinding?
    private var triggerWasSuspended = false

    private var commandIsDown = false
    private var commandWasUsed = false
    private var lastCommandTapTime: TimeInterval = 0

    private let doubleCommandInterval: TimeInterval = 0.35

    override init() {
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
            rootView: ContentView(keyRouter: keyRouter)
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

        applyBackground()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyBackground()
        }

        startCommandMonitor()
        keyRouter.resignInput = { [weak self] in self?.panel.makeFirstResponder(nil) }
        keyRouter.triggerChanged = { [weak self] in self?.updateToggleTrigger() }
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResignKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
        installHotKeyHandler()
        updateToggleTrigger()
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
            keyRouter.closeEditor()
        } else {
            showCue()
        }
    }

    @objc private func panelDidResignKey() {
        keyRouter.panelResignedKey()
    }
    
    func showCue() {
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        keyRouter.shown()
    }
    
    private func startCommandMonitor() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleKeyboardEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            self.handleKeyboardEvent(event)
            guard self.panel.isKeyWindow else { return event }
            if event.type == .keyDown,
               let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                return event
            }
            if self.keyRouter.handle(event) { return nil }
            return event
        }
    }
    
    private func handleKeyboardEvent(_ event: NSEvent) {
        guard !keyRouter.toggleIsSuspended,
              let trigger = keyRouter.keys.bindings[.toggle], trigger.kind == .doubleTap else { return }
        let target = trigger.flags
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
            let flags = CueKeyRouter.modifiers(event)
            let commandDownNow = flags.contains(target)

            if commandDownNow && !commandIsDown {
                // ⌘を押した
                commandIsDown = true
                commandWasUsed = flags != target

            } else if !commandDownNow && commandIsDown {
                // ⌘を離した
                commandIsDown = false

                if commandWasUsed || !flags.isEmpty {
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

    private func installHotKeyHandler() {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x43756539, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let controller = Unmanaged<CuePanelController>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    controller.hotKeyIsDown = false
                } else if !controller.hotKeyIsDown, !controller.keyRouter.toggleIsSuspended {
                    controller.hotKeyIsDown = true
                    controller.toggleCue()
                }
            }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        if status != noErr { keyRouter.hotKeyError = "Could not install global shortcut handler (\(status))." }
    }

    private func updateToggleTrigger() {
        let trigger = keyRouter.keys.bindings[.toggle]
        let suspended = keyRouter.toggleIsSuspended
        guard configuredTrigger != trigger || triggerWasSuspended != suspended else { return }
        configuredTrigger = trigger
        triggerWasSuspended = suspended
        commandIsDown = false
        commandWasUsed = false
        lastCommandTapTime = 0
        hotKeyIsDown = false
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard hotKeyHandler != nil else { return }
        keyRouter.hotKeyError = nil
        guard !suspended, let trigger, trigger.kind == .combo else { return }
        var flags: UInt32 = 0
        if trigger.flags.contains(.command) { flags |= UInt32(cmdKey) }
        if trigger.flags.contains(.option) { flags |= UInt32(optionKey) }
        if trigger.flags.contains(.control) { flags |= UInt32(controlKey) }
        if trigger.flags.contains(.shift) { flags |= UInt32(shiftKey) }
        let status = RegisterEventHotKey(UInt32(trigger.keyCode), flags,
                                         EventHotKeyID(signature: 0x43756539, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            keyRouter.hotKeyError = "Could not register global shortcut (\(status)). Choose another shortcut or reopen Cue."
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
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
