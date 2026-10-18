import Foundation

// Apple Watch <-> iPhone exchange over WatchConnectivity, and the Watch's local state.
// The iPhone list stays the source of truth; the Watch only shows and adds Cues.
enum WatchSync {
    nonisolated static let cueKey = "cue"  // Watch -> iPhone, transferUserInfo
    nonisolated static let snapshotKey = "snapshot"  // iPhone -> Watch, application context
    static let displayLimit = 20

    // Trimmed text, or nil when there is nothing to save.
    static func captureText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// The iPhone's current Cues as sent to the Watch. Replaced as a whole, never a log.
struct WatchSnapshot: Codable {
    var cues: [CueItem]      // newest first
    var received: [UUID]     // Watch Cues the iPhone has received, even if removed there since

    // storedCues in the iPhone's saved order (oldest first).
    init(storedCues: [CueItem], received: [UUID]) {
        self.cues = Array(storedCues.suffix(WatchSync.displayLimit).reversed())
        self.received = received
    }
}

// Watch-local state, one file in the App Group container shared with the complication.
struct WatchCueState: Codable {
    var snapshot: [CueItem] = []   // from the iPhone, newest first
    var pending: [CueItem] = []    // captured on the Watch, not yet confirmed by a snapshot

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.takayashou.cue")?
            .appendingPathComponent("WatchCues.json")
    }

    static func read(from url: URL?) -> WatchCueState {
        guard let url,
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WatchCueState.self, from: data) else {
            return WatchCueState()
        }
        return state
    }

    func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    // Snapshot plus pending Cues it does not contain yet, newest first.
    var displayCues: [CueItem] {
        let snapshotIDs = Set(snapshot.map(\.id))
        let merged = pending.filter { !snapshotIDs.contains($0.id) } + snapshot
        let sorted = merged.enumerated().sorted { a, b in
            let aDate = a.element.createdAt ?? .distantPast
            let bDate = b.element.createdAt ?? .distantPast
            return aDate != bDate ? aDate > bDate : a.offset < b.offset
        }
        return sorted.prefix(WatchSync.displayLimit).map(\.element)
    }

    // A pending Cue is resolved once the iPhone shows or reports it.
    mutating func apply(_ newSnapshot: WatchSnapshot) {
        let resolved = Set(newSnapshot.cues.map(\.id)).union(newSnapshot.received)
        pending.removeAll { resolved.contains($0.id) }
        snapshot = Array(newSnapshot.cues.prefix(WatchSync.displayLimit))
    }
}
