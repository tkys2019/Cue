import Foundation

// Compile with Shared/CueItem.swift and Shared/WatchSync.swift. Uses a temporary file only.
@main
struct WatchSyncRegression {
    static func main() throws {
        precondition(WatchSync.captureText("") == nil)
        precondition(WatchSync.captureText(" \n\t ") == nil)
        precondition(WatchSync.captureText("  牛乳買う \n") == "牛乳買う")

        let old = CueItem(text: "old", createdAt: Date(timeIntervalSince1970: 100))
        let phone = CueItem(text: "phone", createdAt: Date(timeIntervalSince1970: 200))
        let watch = CueItem(text: "watch", createdAt: Date(timeIntervalSince1970: 300))

        // The iPhone sends its stored order (oldest first) as newest first.
        let snapshot = WatchSnapshot(storedCues: [old, phone], received: [])
        precondition(snapshot.cues.map(\.text) == ["phone", "old"])
        let many = (0..<30).map { CueItem(text: "\($0)") }
        precondition(WatchSnapshot(storedCues: many, received: []).cues.map(\.text).first == "29")
        precondition(WatchSnapshot(storedCues: many, received: []).cues.count == WatchSync.displayLimit)

        // A pending Cue stays visible until a snapshot contains it, without duplicates.
        var state = WatchCueState()
        state.pending.append(watch)
        state.apply(snapshot)
        precondition(state.pending.count == 1)
        precondition(state.displayCues.map(\.text) == ["watch", "phone", "old"])
        state.apply(WatchSnapshot(storedCues: [old, phone, watch], received: [watch.id]))
        precondition(state.pending.isEmpty)
        precondition(state.displayCues.map(\.text) == ["watch", "phone", "old"])

        // Pending and snapshot with the same ID show once.
        var both = WatchCueState()
        both.pending = [watch]
        both.snapshot = [watch, phone]
        precondition(both.displayCues.map(\.id) == [watch.id, phone.id])

        // Received but already removed on the iPhone: resolved, not shown forever.
        var removed = WatchCueState()
        removed.pending = [watch]
        removed.apply(WatchSnapshot(storedCues: [old], received: [watch.id]))
        precondition(removed.pending.isEmpty && removed.displayCues.map(\.text) == ["old"])

        // Newest first, also for a Watch Cue newer than the snapshot.
        var newest = WatchCueState()
        newest.snapshot = [phone, old]
        newest.pending = [watch]
        precondition(newest.displayCues.first?.id == watch.id)

        // Persisted state round-trips and keeps IDs.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WatchCues.\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        precondition(WatchCueState.read(from: url).displayCues.isEmpty)
        try newest.write(to: url)
        let read = WatchCueState.read(from: url)
        precondition(read.pending.map(\.id) == [watch.id] && read.snapshot.map(\.id) == [phone.id, old.id])

        print("WatchSync regression checks passed")
    }
}
