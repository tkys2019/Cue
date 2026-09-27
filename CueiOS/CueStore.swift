import Foundation
import Combine
import WidgetKit

@MainActor
final class CueStore: ObservableObject {
    @Published private(set) var cues: [CueItem] = []

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults
    private let reloadWidget: () -> Void

    init(
        defaults: UserDefaults = UserDefaults(suiteName: "group.com.takayashou.cue") ?? .standard,
        legacyDefaults: UserDefaults = .standard,
        reloadWidget: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "CueWidget")
        }
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        self.reloadWidget = reloadWidget
    }

    func load() {
        migrateFromStandardDefaults()
        cues = readSavedCues()
    }

    func add(_ text: String) {
        // Read before each mutation, as before, to preserve other saved changes.
        var saved = readSavedCues()
        saved.append(CueItem(text: text))
        save(saved)
    }

    func delete(_ cue: CueItem) {
        var saved = readSavedCues()
        saved.removeAll { $0.id == cue.id }
        save(saved)
    }

    private func save(_ saved: [CueItem]) {
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "cues")
        }
        reloadWidget()
        cues = saved
    }

    private func readSavedCues() -> [CueItem] {
        guard let data = defaults.data(forKey: "cues"),
              let saved = try? JSONDecoder().decode([CueItem].self, from: data) else {
            return []
        }
        return saved
    }

    private func migrateFromStandardDefaults() {
        // Copy bytes only when the destination is absent; retain the old data.
        guard defaults.data(forKey: "cues") == nil,
              let oldData = legacyDefaults.data(forKey: "cues") else { return }
        defaults.set(oldData, forKey: "cues")
        reloadWidget()
    }
}
