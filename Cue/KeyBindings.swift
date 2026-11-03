import Foundation

nonisolated enum CueKeyContext: String, CaseIterable {
    case input, list, selecting
}

nonisolated enum CueKeyAction: String, CaseIterable, Codable {
    case toggle, save, toList, up, down, back, copy, toggleSelect, selectAll
    case copySelected, reminders, delete, endSelect, openShortcuts

    var title: String {
        switch self {
        case .toggle: "Show / Hide Cue"
        case .save: "Save"
        case .toList: "Go to List"
        case .up: "Move Up"
        case .down: "Move Down"
        case .back: "Back to Input"
        case .copy: "Copy"
        case .toggleSelect: "Toggle Selection"
        case .selectAll: "Select All"
        case .copySelected: "Copy Selected"
        case .reminders: "Send to Reminders"
        case .delete: "Delete"
        case .endSelect: "End Selection"
        case .openShortcuts: "Keyboard Shortcuts"
        }
    }

    var contexts: Set<CueKeyContext> {
        switch self {
        case .toggle, .openShortcuts: Set(CueKeyContext.allCases)
        case .save, .toList: [.input]
        case .up, .down, .toggleSelect, .selectAll, .reminders: [.list, .selecting]
        case .back, .copy, .delete: [.list]
        case .copySelected, .endSelect: [.selecting]
        }
    }

    var contextTitle: String {
        self == .toggle ? "Global" : CueKeyContext.allCases.filter { contexts.contains($0) }.map(\.rawValue).joined(separator: ", ")
    }

    var isRequired: Bool {
        [.toggle, .save, .toList, .up, .down, .back, .openShortcuts].contains(self)
    }

    var allowsRepeat: Bool { self == .up || self == .down }
}

nonisolated struct CueKeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt
    static let shift = Self(rawValue: 1 << 17)
    static let control = Self(rawValue: 1 << 18)
    static let option = Self(rawValue: 1 << 19)
    static let command = Self(rawValue: 1 << 20)
    static let function = Self(rawValue: 1 << 23)
    static let supported: Self = [.shift, .control, .option, .command, .function]

    var normalized: Self { intersection(.supported) }
    var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}

nonisolated struct CueKeyBinding: Codable, Equatable {
    enum Kind: String, Codable { case combo, doubleTap }
    let keyCode: UInt16
    let modifiers: UInt
    let display: String
    let kind: Kind

    init(_ keyCode: UInt16, _ flags: CueKeyModifiers = [], _ display: String, kind: Kind = .combo) {
        self.keyCode = keyCode
        modifiers = flags.normalized.rawValue
        self.display = display
        self.kind = kind
    }

    var flags: CueKeyModifiers { CueKeyModifiers(rawValue: modifiers).normalized }

    static func normalizedKeyCode(_ keyCode: UInt16) -> UInt16 {
        keyCode == 76 ? 36 : keyCode
    }

    func matches(keyCode: UInt16, modifiers: CueKeyModifiers) -> Bool {
        kind == .combo && Self.normalizedKeyCode(self.keyCode) == Self.normalizedKeyCode(keyCode) && flags == modifiers.normalized
    }

    func conflicts(with other: Self) -> Bool {
        kind == other.kind && flags == other.flags &&
            (kind == .doubleTap || Self.normalizedKeyCode(keyCode) == Self.normalizedKeyCode(other.keyCode))
    }

    static func doubleTap(_ modifier: CueKeyModifiers) -> Self {
        let code: UInt16 = modifier == .command ? 55 : modifier == .option ? 58 : 59
        return Self(code, modifier, modifier.symbols + modifier.symbols, kind: .doubleTap)
    }
}

nonisolated enum CueKeyRules {
    static let defaults: [CueKeyAction: CueKeyBinding] = [
        .toggle: .doubleTap(.command), .save: .init(36, [], "↩"),
        .toList: .init(45, .control, "⌃N"), .up: .init(35, .control, "⌃P"),
        .down: .init(45, .control, "⌃N"), .back: .init(53, [], "⎋"),
        .copy: .init(36, [], "↩"), .toggleSelect: .init(49, [], "␣"),
        .selectAll: .init(0, .command, "⌘A"), .copySelected: .init(8, .command, "⌘C"),
        .reminders: .init(15, .command, "⌘R"), .delete: .init(51, .command, "⌘⌫"),
        .endSelect: .init(53, [], "⎋"), .openShortcuts: .init(43, .command, "⌘,")
    ]

    static func problem(for candidate: CueKeyBinding?, action: CueKeyAction,
                        bindings: [CueKeyAction: CueKeyBinding]) -> String? {
        guard let key = candidate else { return action.isRequired ? "Required shortcut" : nil }
        let flags = key.flags
        guard key.modifiers == flags.rawValue, key.keyCode <= 127, !key.display.isEmpty else {
            return "Invalid shortcut"
        }
        if key.kind == .doubleTap {
            guard action == .toggle, [CueKeyModifiers.command, .option, .control].contains(flags),
                  key.keyCode == CueKeyBinding.doubleTap(flags).keyCode else {
                return "Double tap requires ⌘, ⌥ or ⌃"
            }
        } else {
            if [125, 126].contains(key.keyCode), flags.isEmpty { return "Reserved for navigation" }
            if isReserved(key) { return "Reserved by macOS" }
            if action == .toggle, flags.intersection([.command, .option, .control]).isEmpty {
                return "Include ⌘, ⌥ or ⌃"
            }
            if action.contexts.contains(.input), breaksInput(key, action: action) {
                return "Reserved for text input"
            }
        }
        for other in CueKeyAction.allCases where other != action {
            if !action.contexts.isDisjoint(with: other.contexts),
               let assigned = bindings[other], key.conflicts(with: assigned) {
                return "Used by \(other.title)"
            }
        }
        return nil
    }

    static func action(keyCode: UInt16, modifiers: CueKeyModifiers, context: CueKeyContext,
                       bindings: [CueKeyAction: CueKeyBinding]) -> CueKeyAction? {
        if modifiers.normalized.isEmpty {
            if keyCode == 125 { return context == .input ? .toList : .down }
            if keyCode == 126, context != .input { return .up }
        }
        return CueKeyAction.allCases.first {
            $0 != .toggle && $0.contexts.contains(context) &&
                bindings[$0]?.matches(keyCode: keyCode, modifiers: modifiers) == true
        }
    }

    private static func isReserved(_ key: CueKeyBinding) -> Bool {
        let code = key.keyCode
        let flags = key.flags
        if flags.contains(.function) || [102, 104, 55, 54, 56, 60, 58, 61, 59, 62, 63, 57].contains(code) { return true }
        if flags.isEmpty, [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(code) { return true }
        if flags == .command, [12, 48, 49, 4, 46, 50].contains(code) { return true }
        if flags == [.command, .shift], [20, 21, 23].contains(code) { return true }
        if (flags == .control || flags == [.control, .option]), code == 49 { return true }
        return flags == .control && [123, 124, 125, 126].contains(code)
    }

    private static func breaksInput(_ key: CueKeyBinding, action: CueKeyAction) -> Bool {
        let code = key.keyCode
        let flags = key.flags
        let printable = (0...50).contains(code) && ![36, 48].contains(code) ||
            [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95].contains(code)
        if printable, flags.isEmpty || flags == .shift || flags == .option { return true }
        if flags == .command, [0, 8, 9, 7, 6, 51, 123, 124, 125, 126].contains(code) { return true }
        if flags == [.command, .shift], [6, 123, 124].contains(code) { return true }
        if flags == .option, [51, 123, 124].contains(code) { return true }
        if flags == [.option, .shift], [123, 124].contains(code) { return true }
        if flags.isEmpty, [51, 117, 123, 124, 48, 115, 119].contains(code) { return true }
        if flags == .shift, [49, 123, 124].contains(code) { return true }
        if flags == .control, [38, 40, 37, 41, 0, 14, 3, 11, 2, 4].contains(code) { return true }
        if flags == .control, [45, 35].contains(code) { return action != .toList }
        return false
    }
}

// Foundation-only persistence; callers inject an isolated defaults suite in tests.
nonisolated final class CueKeyBindings {
    private let defaults: UserDefaults
    private(set) var bindings = CueKeyRules.defaults
    private(set) var notes: [CueKeyAction: String] = [:]
    private(set) var loadNotice: String?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let stored = defaults.object(forKey: "keyBindings") else { return }
        guard let data = stored as? Data,
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let header = try? JSONDecoder().decode(Header.self, from: data), header.version == 1,
              let values = document["bindings"] as? [String: Any] else {
            loadNotice = "Could not read shortcuts. Using defaults until you save a change."
            return
        }
        for action in CueKeyAction.allCases {
            guard let value = values[action.rawValue] else { continue }
            if value is NSNull {
                bindings.removeValue(forKey: action)
            } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                      let key = try? JSONDecoder().decode(CueKeyBinding.self, from: data) {
                bindings[action] = key
            } else {
                notes[action] = "Invalid saved shortcut; using default"
            }
        }
        // Restoring a default can expose another conflict, so validate to a fixed point.
        for _ in 0...CueKeyAction.allCases.count {
            let invalid = CueKeyAction.allCases.filter {
                CueKeyRules.problem(for: bindings[$0], action: $0, bindings: bindings) != nil
            }
            if invalid.isEmpty { return }
            var changed = false
            for action in invalid {
                notes[action] = "\(CueKeyRules.problem(for: bindings[action], action: action, bindings: bindings) ?? "Invalid shortcut"); using default"
                if bindings[action] != CueKeyRules.defaults[action] { changed = true }
                bindings[action] = CueKeyRules.defaults[action]
            }
            if !changed { break }
        }
        bindings = CueKeyRules.defaults
        loadNotice = "Conflicting saved shortcuts; using defaults."
    }

    @discardableResult
    func set(_ key: CueKeyBinding?, for action: CueKeyAction) -> String? {
        if let problem = CueKeyRules.problem(for: key, action: action, bindings: bindings) { return problem }
        bindings[action] = key
        notes.removeValue(forKey: action)
        loadNotice = nil
        save()
        return nil
    }

    func reset() {
        bindings = CueKeyRules.defaults
        notes = [:]
        loadNotice = nil
        save()
    }

    private func save() {
        let values = Dictionary(uniqueKeysWithValues: CueKeyAction.allCases.map { ($0.rawValue, bindings[$0]) })
        if let data = try? JSONEncoder().encode(Document(version: 1, bindings: values)) {
            defaults.set(data, forKey: "keyBindings")
        }
    }

    private struct Document: Encodable {
        let version: Int
        let bindings: [String: CueKeyBinding?]
    }

    private struct Header: Decodable { let version: Int }
}
