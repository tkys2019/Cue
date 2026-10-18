import Foundation
import Combine
import WidgetKit

@MainActor
final class WatchCueStore: ObservableObject {
    static let shared = WatchCueStore()

    @Published private(set) var cues: [CueItem] = []
    private var state = WatchCueState()
    private let fileURL = WatchCueState.fileURL

    var pending: [CueItem] {
        state.pending
    }

    func load() {
        state = WatchCueState.read(from: fileURL)
        cues = state.displayCues
    }

    // Saved on the Watch first; the iPhone gets it later. Returns nil for empty text.
    func capture(_ text: String) throws -> CueItem? {
        guard let text = WatchSync.captureText(text) else { return nil }
        let cue = CueItem(text: text)
        var newState = state
        newState.pending.append(cue)
        try save(newState)
        return cue
    }

    func apply(_ snapshot: WatchSnapshot) {
        var newState = state
        newState.apply(snapshot)
        try? save(newState)
    }

    private func save(_ newState: WatchCueState) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try newState.write(to: fileURL)
        state = newState
        let display = newState.displayCues
        let changed = display.map(\.id) != cues.map(\.id) || display.map(\.text) != cues.map(\.text)
        cues = display
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: "CueWatchWidget")
        }
    }
}
