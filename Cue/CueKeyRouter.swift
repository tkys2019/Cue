import AppKit
import Combine
import SwiftUI

final class CueKeyRouter: ObservableObject {
    enum EditorPhase: Equatable {
        case closed, browsing, recording(CueKeyAction), confirming(CueKeyAction, CueKeyBinding), confirmReset
    }

    let keys: CueKeyBindings
    let commands = PassthroughSubject<CueKeyAction, Never>()
    let panelShown = PassthroughSubject<Void, Never>()
    @Published var context: CueKeyContext = .input
    @Published private(set) var editor: EditorPhase = .closed
    @Published var editorRow = 0
    @Published private(set) var message: String?
    @Published var hotKeyError: String?
    var triggerChanged: (() -> Void)?
    var resignInput: (() -> Void)?
    private var recordingModifier: CueKeyModifiers = []
    private var recordingTapTime: TimeInterval = 0
    private var lastRecordingModifier: CueKeyModifiers = []
    private var recordingModifierUsed = false

    init(defaults: UserDefaults = .standard) {
        keys = CueKeyBindings(defaults: defaults)
    }

    var editorIsOpen: Bool { editor != .closed }
    var toggleIsSuspended: Bool {
        switch editor {
        case .recording, .confirming, .confirmReset: true
        default: false
        }
    }

    func display(_ action: CueKeyAction) -> String { keys.bindings[action]?.display ?? "" }

    func shown() {
        closeEditor()
        context = .input
        panelShown.send()
    }

    func openEditor() {
        resignInput?()
        editorRow = 0
        setEditor(.browsing)
    }

    func closeEditor() { setEditor(.closed) }

    func panelResignedKey() {
        if toggleIsSuspended { setEditor(.browsing) }
    }

    func startRecording(_ action: CueKeyAction) {
        editorRow = CueKeyAction.allCases.firstIndex(of: action) ?? 0
        recordingModifier = []
        recordingTapTime = 0
        lastRecordingModifier = []
        recordingModifierUsed = false
        setEditor(.recording(action))
        announce("Recording \(action.title). Press a shortcut.")
    }

    func requestReset() {
        setEditor(.confirmReset)
        announce("Reset all shortcuts? Return to reset, Escape to cancel.")
    }

    func handle(_ event: NSEvent) -> Bool {
        if editorIsOpen { return handleEditor(event) }
        guard event.type == .keyDown else { return false }
        let flags = Self.modifiers(event)
        if let action = CueKeyRules.action(keyCode: event.keyCode, modifiers: flags,
                                          context: context, bindings: keys.bindings) {
            if !event.isARepeat || action.allowsRepeat { commands.send(action) }
            return true
        }
        if context != .input, flags.isEmpty,
           let text = event.characters, text.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) }) {
            return true
        }
        return false
    }

    private func setEditor(_ phase: EditorPhase) {
        editor = phase
        message = nil
        triggerChanged?()
    }

    private func showMessage(_ text: String) {
        message = text
        announce(text)
    }

    private func handleEditor(_ event: NSEvent) -> Bool {
        if case .recording(let action) = editor {
            if event.type == .keyDown {
                recordingModifierUsed = true
                if !event.isARepeat { confirmCandidate(Self.binding(event), action: action) }
            } else if action == .toggle, event.type == .flagsChanged {
                let flags = Self.modifiers(event)
                if [CueKeyModifiers.command, .option, .control].contains(flags) {
                    if !recordingModifier.isEmpty { recordingModifierUsed = true }
                    recordingModifier = flags
                } else if flags.isEmpty, !recordingModifier.isEmpty {
                    let modifier = recordingModifier
                    recordingModifier = []
                    guard !recordingModifierUsed else {
                        recordingModifierUsed = false
                        recordingTapTime = 0
                        return true
                    }
                    if lastRecordingModifier == modifier, recordingTapTime > 0, event.timestamp - recordingTapTime <= 0.35 {
                        confirmCandidate(.doubleTap(modifier), action: action)
                    } else {
                        recordingTapTime = event.timestamp
                        lastRecordingModifier = modifier
                    }
                } else {
                    recordingModifierUsed = true
                    recordingTapTime = 0
                }
            }
            return true
        }
        guard event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        let plain = Self.modifiers(event).isEmpty
        let keyCode = CueKeyBinding.normalizedKeyCode(event.keyCode)
        switch editor {
        case .browsing:
            guard plain else { return true }
            switch keyCode {
            case 126: editorRow = max(0, editorRow - 1)
            case 125: editorRow = min(CueKeyAction.allCases.count + 1, editorRow + 1)
            case 36:
                if editorRow < CueKeyAction.allCases.count { startRecording(CueKeyAction.allCases[editorRow]) }
                else if editorRow == CueKeyAction.allCases.count { requestReset() }
                else { closeEditor() }
            case 51 where editorRow < CueKeyAction.allCases.count:
                let action = CueKeyAction.allCases[editorRow]
                if let problem = keys.set(nil, for: action) { showMessage(problem) }
                else { objectWillChange.send(); triggerChanged?() }
            case 53: closeEditor()
            default: break
            }
        case .confirming(let action, let candidate):
            if plain, keyCode == 53 { setEditor(.browsing) }
            else if plain, keyCode == 36 {
                if let problem = keys.set(candidate, for: action) { showMessage(problem) }
                else { setEditor(.browsing) }
            }
        case .confirmReset:
            if plain, keyCode == 53 { setEditor(.browsing) }
            else if plain, keyCode == 36 { keys.reset(); setEditor(.browsing) }
        default: break
        }
        return true
    }

    private func confirmCandidate(_ key: CueKeyBinding, action: CueKeyAction) {
        setEditor(.confirming(action, key))
        showMessage(CueKeyRules.problem(for: key, action: action, bindings: keys.bindings)
                    ?? "\(key.display) — Return to save, Escape to cancel")
    }

    static func modifiers(_ event: NSEvent) -> CueKeyModifiers {
        var flags = CueKeyModifiers(rawValue: event.modifierFlags.rawValue).normalized
        // AppKit marks dedicated navigation/function keys with the function flag too.
        if [36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126,
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(event.keyCode) {
            flags.remove(.function)
        }
        return flags
    }

    private static func binding(_ event: NSEvent) -> CueKeyBinding {
        let flags = modifiers(event)
        let keyCode = CueKeyBinding.normalizedKeyCode(event.keyCode)
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
                                          117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                          115: "↖", 119: "↘", 116: "⇞", 121: "⇟"]
        let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        let name: String
        if let symbol = special[keyCode] { name = symbol }
        else if let index = functionKeys.firstIndex(of: keyCode) { name = "F\(index + 1)" }
        else { name = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(keyCode)" }
        return CueKeyBinding(keyCode, flags, flags.symbols + name)
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

struct CueShortcutsEditor: View {
    @ObservedObject var router: CueKeyRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Keyboard Shortcuts").font(.headline)
            if let notice = router.keys.loadNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = router.hotKeyError { Text(error).font(.caption).foregroundStyle(.red) }
            Text(instructions).font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(CueKeyAction.allCases.enumerated()), id: \.element) { index, action in
                            Button { router.startRecording(action) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(action.title)
                                        Text(action.contextTitle).font(.caption2).foregroundStyle(.secondary)
                                        if let note = router.keys.notes[action] {
                                            Text(note).font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(rowDisplay(action)).foregroundStyle(.secondary)
                                }
                                .padding(4)
                                .background(router.editorRow == index ? Color.accentColor.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .disabled(router.toggleIsSuspended || router.editor == .confirmReset)
                            .id(index)
                            .accessibilityLabel("\(action.title), \(router.display(action).isEmpty ? "Unassigned" : router.display(action))")
                        }
                        Button("Reset to Defaults") { router.requestReset() }
                            .disabled(router.toggleIsSuspended)
                            .background(router.editorRow == 14 ? Color.accentColor.opacity(0.12) : .clear)
                            .id(14)
                        Button("Done") { router.closeEditor() }
                            .background(router.editorRow == 15 ? Color.accentColor.opacity(0.12) : .clear)
                            .id(15)
                    }
                }
                .onChange(of: router.editorRow) { _, row in proxy.scrollTo(row) }
            }
            if let message = router.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal)
    }

    private var instructions: String {
        switch router.editor {
        case .recording: "Press a shortcut (including Return or Escape)."
        case .confirming: "Return: save · Escape: cancel"
        case .confirmReset: "Reset all shortcuts? Return: reset · Escape: cancel"
        default: "↑↓: move · Return: record · Delete: unassign · Escape: done"
        }
    }

    private func rowDisplay(_ action: CueKeyAction) -> String {
        switch router.editor {
        case .recording(let current) where current == action: return "Recording…"
        case .confirming(let current, let key) where current == action: return key.display
        default: return router.display(action).isEmpty ? "—" : router.display(action)
        }
    }
}
