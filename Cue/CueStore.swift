import Foundation
import Combine

@MainActor
final class CueStore: ObservableObject {
    @Published private(set) var cues: [CueItem] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() {
        if let data = defaults.data(forKey: "cues"),
           let saved = try? JSONDecoder().decode([CueItem].self, from: data) {
            cues = saved
        }
    }

    func add(_ text: String) {
        cues.append(CueItem(text: text))
        save()
    }

    func delete(_ cue: CueItem) {
        cues.removeAll { $0.id == cue.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cues) {
            defaults.set(data, forKey: "cues")
        }
    }
}
