import Foundation

// swiftc Tests/KeyBindingsRegression.swift Cue/KeyBindings.swift -o <scratch>/tests/KeyBindingsRegression
// Uses only its own UserDefaults suite, never the app's defaults domain.
@main
struct KeyBindingsRegression {
    static func main() throws {
        let name = "CueKeyBindingsRegression.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label)
            checks += 1
        }
        func load(_ json: String) -> CueKeyBindings {
            defaults.set(Data(json.utf8), forKey: "keyBindings")
            return CueKeyBindings(defaults: defaults)
        }
        func json(_ key: CueKeyBinding) throws -> String {
            String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
        }
        func problem(_ key: CueKeyBinding?, _ action: CueKeyAction,
                     _ bindings: [CueKeyAction: CueKeyBinding] = CueKeyRules.defaults) -> String? {
            CueKeyRules.problem(for: key, action: action, bindings: bindings)
        }

        let initial = CueKeyBindings(defaults: defaults)
        check(defaults.object(forKey: "keyBindings") == nil, "absent data is not written")
        check(CueKeyAction.allCases.count == 14 && initial.bindings.count == 14, "all fourteen actions")
        let expected: [(CueKeyAction, UInt16, CueKeyModifiers, String)] = [
            (.save, 36, [], "↩"), (.toList, 45, .control, "⌃N"), (.up, 35, .control, "⌃P"),
            (.down, 45, .control, "⌃N"), (.back, 53, [], "⎋"), (.copy, 36, [], "↩"),
            (.toggleSelect, 49, [], "␣"), (.selectAll, 0, .command, "⌘A"),
            (.copySelected, 8, .command, "⌘C"), (.reminders, 15, .command, "⌘R"),
            (.delete, 51, .command, "⌘⌫"), (.endSelect, 53, [], "⎋"), (.openShortcuts, 43, .command, "⌘,")
        ]
        for (action, code, flags, display) in expected {
            check(initial.bindings[action] == CueKeyBinding(code, flags, display), "default \(action)")
        }
        check(initial.bindings[.toggle] == .doubleTap(.command), "default double Command")
        for action in CueKeyAction.allCases {
            check(problem(initial.bindings[action], action) == nil, "valid default \(action)")
            check((problem(nil, action) != nil) == action.isRequired, "required \(action)")
            check(action.allowsRepeat == (action == .up || action == .down), "repeat policy \(action)")
        }
        initial.reset()
        let saved = defaults.data(forKey: "keyBindings")!
        let document = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        check(document["version"] as? Int == 1, "version one")
        check(CueKeyBindings(defaults: defaults).bindings == initial.bindings, "default round trip")
        let combination = CueKeyBinding(36, .command, "⌘↩")
        check(initial.set(combination, for: .save) == nil, "remap save")
        check(initial.set(nil, for: .copy) == nil, "unassign optional")
        check(initial.set(nil, for: .save) != nil && initial.bindings[.save] == combination, "rejection retains previous value")
        let reloaded = CueKeyBindings(defaults: defaults)
        check(reloaded.bindings[.save] == combination && reloaded.bindings[.copy] == nil, "custom and null round trip")
        let customData = defaults.data(forKey: "keyBindings")!
        let customDocument = try JSONSerialization.jsonObject(with: customData) as! [String: Any]
        check((customDocument["bindings"] as! [String: Any])["copy"] is NSNull, "explicit JSON null")

        let partial = load("{\"version\":1,\"bindings\":{\"save\":\(try json(combination)),\"futureAction\":{\"anything\":true}}}")
        check(partial.bindings[.save] == combination && partial.bindings[.down] == CueKeyRules.defaults[.down], "missing defaults and unknown action")
        for invalid in ["not JSON", "[]", "{\"version\":2,\"bindings\":{}}", "{\"version\":true,\"bindings\":{}}",
                        "{\"bindings\":{}}", "{\"version\":1,\"bindings\":[]}"] {
            let loaded = load(invalid)
            check(loaded.bindings == CueKeyRules.defaults && loaded.loadNotice != nil, "corrupt or unsupported document")
            check(defaults.data(forKey: "keyBindings") == Data(invalid.utf8), "corrupt data is not overwritten")
        }
        defaults.set("wrong type", forKey: "keyBindings")
        check(CueKeyBindings(defaults: defaults).bindings == CueKeyRules.defaults, "wrong stored type")
        check(defaults.string(forKey: "keyBindings") == "wrong type", "wrong stored type retained")
        let nullRequired = load("{\"version\":1,\"bindings\":{\"save\":null,\"copy\":null}}")
        check(nullRequired.bindings[.save] == CueKeyRules.defaults[.save] && nullRequired.notes[.save] != nil, "invalid required null falls back with note")
        check(nullRequired.bindings[.copy] == nil, "optional null is retained")
        let invalidKey = CueKeyBinding(12, .command, "⌘Q")
        let invalidJSON = "{\"version\":1,\"bindings\":{\"save\":\(try json(invalidKey))}}"
        let invalidLoaded = load(invalidJSON)
        check(invalidLoaded.bindings == CueKeyRules.defaults && invalidLoaded.notes[.save] != nil, "reserved saved value falls back")
        check(defaults.data(forKey: "keyBindings") == Data(invalidJSON.utf8), "invalid bindings are not overwritten")
        check(invalidLoaded.set(combination, for: .save) == nil, "explicit change repairs saved data")
        check(CueKeyBindings(defaults: defaults).bindings[.save] == combination, "repair persists only after user change")
        let malformed = load("{\"version\":1,\"bindings\":{\"save\":{\"keyCode\":36}}}")
        check(malformed.bindings[.save] == CueKeyRules.defaults[.save] && malformed.notes[.save] != nil, "malformed binding noted")
        let duplicate = load("{\"version\":1,\"bindings\":{\"down\":\(try json(CueKeyRules.defaults[.up]!))}}")
        for action in CueKeyAction.allCases {
            check(problem(duplicate.bindings[action], action, duplicate.bindings) == nil, "loaded duplicates are repaired \(action)")
        }
        check(duplicate.notes[.down] != nil, "duplicate recovery note")
        let cascade = load("{\"version\":1,\"bindings\":{\"save\":\(try json(invalidKey)),\"openShortcuts\":\(try json(CueKeyRules.defaults[.save]!))}}")
        for action in CueKeyAction.allCases {
            check(problem(cascade.bindings[action], action, cascade.bindings) == nil, "fallback conflict cascade \(action)")
        }

        check(problem(CueKeyRules.defaults[.up], .down)?.hasPrefix("Used by") == true, "overlapping contexts reject duplicate")
        check(problem(CueKeyRules.defaults[.save], .copy) == nil, "exclusive input/list share Return")
        check(problem(CueKeyRules.defaults[.back], .endSelect) == nil, "exclusive list/selecting share Escape")
        check(problem(CueKeyRules.defaults[.toList], .down) == nil, "exclusive input/list share Control N")
        check(problem(CueKeyRules.defaults[.openShortcuts], .toggle)?.hasPrefix("Used by") == true, "global conflicts with all contexts")
        check(problem(.init(76, [], "⌤"), .openShortcuts)?.hasPrefix("Used by") == true, "Enter alias conflicts with Return in overlapping contexts")
        check(problem(.init(76, [], "⌤"), .copy) == nil, "Enter alias can share Return in exclusive contexts")
        for flags: CueKeyModifiers in [.command, .option, .control] {
            check(problem(.doubleTap(flags), .toggle) == nil, "allowed double tap \(flags)")
            check(problem(.doubleTap(flags), .copy) != nil, "double tap only toggle")
        }
        for flags: CueKeyModifiers in [[], .shift, .function, [.command, .option]] {
            check(problem(CueKeyBinding(55, flags, "tap", kind: .doubleTap), .toggle) != nil, "invalid double tap modifier")
        }
        check(problem(.init(17, .shift, "⇧T"), .toggle) != nil, "toggle needs modifier beyond Shift")
        check(problem(.init(17, [.command, .option], "⌥⌘T"), .toggle) == nil, "global combination allowed")

        let reserved: [(UInt16, CueKeyModifiers)] = [
            (12, .command), (48, .command), (49, .command), (49, .control), (49, [.control, .option]),
            (4, .command), (46, .command), (50, .command), (20, [.command, .shift]),
            (21, [.command, .shift]), (23, [.command, .shift]), (123, .control), (124, .control),
            (125, .control), (126, .control), (102, []), (104, []), (63, []), (0, .function)
        ]
        for (code, flags) in reserved {
            check(problem(.init(code, flags, "reserved"), .copy) != nil, "reserved key \(code)/\(flags)")
        }
        for code: UInt16 in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111] {
            check(problem(.init(code, [], "F"), .copy) != nil, "bare function key \(code)")
        }
        for action in CueKeyAction.allCases {
            for code: UInt16 in [125, 126] {
                check(problem(.init(code, [], "arrow"), action) == "Reserved for navigation", "fixed arrows reserved for \(action)")
            }
        }
        let editing: [(UInt16, CueKeyModifiers)] = [
            (0, []), (49, []), (0, .shift), (0, .option), (49, .option), (82, []),
            (0, .command), (8, .command), (9, .command), (7, .command), (6, .command),
            (6, [.command, .shift]), (51, .command), (51, .option), (51, []), (117, []),
            (123, []), (124, []), (123, .command), (124, .command), (123, .option), (124, .option),
            (48, []), (49, .shift), (38, .control), (40, .control), (37, .control), (41, .control)
        ]
        let additionalEditing: [(UInt16, CueKeyModifiers)] = [
            (0, .control), (14, .control), (3, .control), (11, .control), (2, .control), (4, .control),
            (123, .shift), (124, .shift), (123, [.command, .shift]), (124, [.command, .shift]),
            (123, [.option, .shift]), (124, [.option, .shift]), (126, .command), (125, .command),
            (115, []), (119, [])
        ]
        for action: CueKeyAction in [.save, .toList, .openShortcuts, .toggle] {
            for (code, flags) in editing {
                check(problem(.init(code, flags, "text editing"), action) != nil, "input preservation \(action)/\(code)/\(flags)")
            }
            for (code, flags) in additionalEditing {
                let reason = problem(.init(code, flags, "text editing"), action)
                check(action == .toggle ? reason != nil : reason == "Reserved for text input", "standard editing preserved \(action)/\(code)/\(flags)")
            }
            for code: UInt16 in [35, 45] {
                let key = CueKeyBinding(code, .control, "Control navigation")
                check((problem(key, action) == nil) == (action == .toList), "Control N/P input exception \(action)")
            }
        }
        for (code, flags) in additionalEditing {
            check(problem(.init(code, flags, "list shortcut"), .copy) == nil, "editing restriction only applies to input contexts \(code)/\(flags)")
        }
        check(problem(.init(0, [], "A"), .copy) == nil, "printable list shortcut allowed")
        check(problem(.init(43, .command, "⌘,"), .openShortcuts) == nil, "editor shortcut not reserved")

        var bindings = CueKeyRules.defaults
        bindings[.save] = combination
        check(CueKeyRules.action(keyCode: 36, modifiers: [], context: .input, bindings: bindings) == nil, "Return no longer saves")
        check(CueKeyRules.action(keyCode: 36, modifiers: .command, context: .input, bindings: bindings) == .save, "new save shortcut")
        for context in CueKeyContext.allCases {
            check(CueKeyRules.action(keyCode: 125, modifiers: [], context: context, bindings: [:]) == (context == .input ? .toList : .down), "fixed down regardless of bindings")
            check(CueKeyRules.action(keyCode: 126, modifiers: [], context: context, bindings: [:]) == (context == .input ? nil : .up), "fixed up regardless of bindings")
            check(CueKeyRules.action(keyCode: 43, modifiers: .command, context: context, bindings: bindings) == .openShortcuts, "editor reachable \(context)")
        }
        check(CueKeyRules.action(keyCode: 35, modifiers: .control, context: .input, bindings: bindings) == nil, "Control P passes through in input")
        for context in CueKeyContext.allCases {
            check(CueKeyRules.action(keyCode: 45, modifiers: .control, context: context, bindings: CueKeyRules.defaults) == (context == .input ? .toList : .down), "default Control N routes in \(context)")
            check(CueKeyRules.action(keyCode: 35, modifiers: .control, context: context, bindings: CueKeyRules.defaults) == (context == .input ? nil : .up), "default Control P routes in \(context)")
        }
        for code: UInt16 in [36, 76] {
            check(CueKeyBinding.normalizedKeyCode(code) == 36, "Return/Enter recording key is canonical")
            check(CueKeyRules.action(keyCode: code, modifiers: [], context: .input, bindings: CueKeyRules.defaults) == .save, "default Return/Enter saves")
            check(CueKeyRules.action(keyCode: code, modifiers: [], context: .list, bindings: CueKeyRules.defaults) == .copy, "default Return/Enter copies")
            check(CueKeyRules.action(keyCode: code, modifiers: [], context: .input, bindings: bindings) == nil, "remapped save ignores plain Return/Enter")
            check(CueKeyRules.action(keyCode: code, modifiers: .command, context: .input, bindings: bindings) == .save, "remapped save accepts Command Return/Enter")
        }
        for action in CueKeyAction.allCases {
            for flags: CueKeyModifiers in [[], .command, .option, .control, [.command, .shift]] {
                for storedCode: UInt16 in [36, 76] {
                    let key = CueKeyBinding(storedCode, flags, "Return/Enter")
                    for eventCode: UInt16 in [36, 76] {
                        check(key.matches(keyCode: eventCode, modifiers: flags), "Return/Enter match both ways \(action)/\(flags)")
                        check(!key.matches(keyCode: eventCode, modifiers: flags.symmetricDifference(.shift)), "Return/Enter modifiers remain significant")
                        check(key.conflicts(with: .init(eventCode, flags, "alias")), "Return/Enter conflicts both ways")
                        for context in action.contexts where action != .toggle {
                            check(CueKeyRules.action(keyCode: eventCode, modifiers: flags, context: context, bindings: [action: key]) == action, "Return/Enter route all local operations \(action)/\(context)")
                        }
                    }
                }
            }
        }
        let legacyEnter = CueKeyBinding(76, .command, "⌘⌤")
        let legacyJSON = "{\"version\":1,\"bindings\":{\"save\":\(try json(legacyEnter))}}"
        let legacyLoaded = load(legacyJSON)
        check(legacyLoaded.bindings[.save] == legacyEnter, "loading preserves stored Enter keyCode and display")
        check(defaults.data(forKey: "keyBindings") == Data(legacyJSON.utf8), "Enter normalization does not rewrite stored data")
        check(legacyLoaded.set(legacyEnter, for: .save) == nil, "existing Enter binding remains valid")
        check(CueKeyBindings(defaults: defaults).bindings[.save] == legacyEnter, "stored Enter format round trips unchanged")
        let capsAndNumericPad = CueKeyModifiers(rawValue: CueKeyModifiers.command.rawValue | (1 << 16) | (1 << 21))
        check(combination.matches(keyCode: 36, modifiers: capsAndNumericPad), "normalize non-shortcut flags")
        check(!combination.matches(keyCode: 36, modifiers: [.command, .shift]), "Shift is significant")
        check(combination.matches(keyCode: 76, modifiers: .command), "Enter matches Return")
        check(!combination.matches(keyCode: 48, modifiers: .command), "other physical keyCodes remain significant")
        let otherDisplay = CueKeyBinding(36, .command, "かな display")
        check(combination.conflicts(with: otherDisplay), "display/input source does not affect matching")
        check(otherDisplay.matches(keyCode: 36, modifiers: .command), "K1 ignores recorded display")
        for action in CueKeyAction.allCases {
            initial.reset()
            let custom = CueKeyBinding(17, [.command, .option], "⌥⌘T")
            check(initial.set(custom, for: action) == nil, "all actions remappable: \(action)")
            check(CueKeyBindings(defaults: defaults).bindings[action] == custom, "all remappings persist: \(action)")
        }
        initial.reset()
        check(CueKeyBindings(defaults: defaults).bindings == CueKeyRules.defaults, "Reset persists all defaults")
        print("KeyBindings regression checks passed (\(checks) checks)")
    }
}
