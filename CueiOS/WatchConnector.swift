import Foundation
import Combine
import WatchConnectivity

// Receives Cues captured on Apple Watch and sends the latest Cues back for display.
final class WatchConnector: NSObject, WCSessionDelegate {
    static let shared = WatchConnector()

    private weak var store: CueStore?
    private var storeObservation: AnyCancellable?
    private let receivedKey = "watchReceivedIDs"

    // Remembered so a resent Cue is not added again after it was removed here.
    private var receivedIDs: [UUID] {
        get {
            (UserDefaults.standard.stringArray(forKey: receivedKey) ?? []).compactMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue.suffix(100).map(\.uuidString), forKey: receivedKey)
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // The visible list's store, so Watch Cues appear without reloading.
    // Call after the store has loaded.
    func attach(_ store: CueStore) {
        self.store = store
        storeObservation = store.$cues.sink { [weak self] cues in
            self?.sendSnapshot(cues)
        }
    }

    private func currentStore() -> CueStore {
        if let store {
            return store
        }
        let store = CueStore()
        store.load()
        return store
    }

    private func receive(_ data: Data) {
        guard let cue = try? JSONDecoder().decode(CueItem.self, from: data) else { return }
        let store = currentStore()
        if !receivedIDs.contains(cue.id) {
            receivedIDs.append(cue.id)
            store.receive(cue)
        }
        sendSnapshot(store.cues)
    }

    private func sendSnapshot(_ cues: [CueItem]) {
        let session = WCSession.default
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(WatchSnapshot(storedCues: cues, received: receivedIDs)) else {
            return
        }
        // Not reaching the Watch now is fine; the latest context is delivered later.
        try? session.updateApplicationContext([WatchSync.snapshotKey: data])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.sendSnapshot(self.currentStore().cues)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.sendSnapshot(self.currentStore().cues)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchSync.cueKey] as? Data else { return }
        Task { @MainActor in
            self.receive(data)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
