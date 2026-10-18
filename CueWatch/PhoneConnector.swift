import Foundation
import WatchConnectivity

// Sends Watch Cues to the iPhone in the background and receives the iPhone's latest Cues.
// Nothing here is shown to the user: undelivered Cues simply stay pending.
final class PhoneConnector: NSObject, WCSessionDelegate {
    static let shared = PhoneConnector()

    func activate() {
        guard WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Queued by the system and delivered whenever the iPhone becomes reachable.
    func send(_ cue: CueItem) {
        let session = WCSession.default
        // Before activation, pending Cues are sent once it completes.
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(cue) else { return }
        session.transferUserInfo([WatchSync.cueKey: data])
    }

    // Keeps a background launch alive until queued iPhone data has arrived.
    func receivePendingContent() async {
        activate()
        let session = WCSession.default
        var waited = 0
        while (session.activationState != .activated || session.hasContentPending) && waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
    }

    private func sendUnqueuedPending() {
        let queued = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { transfer in
            (transfer.userInfo[WatchSync.cueKey] as? Data)
                .flatMap { try? JSONDecoder().decode(CueItem.self, from: $0) }?.id
        })
        // The iPhone ignores Cues it has already received.
        for cue in WatchCueStore.shared.pending where !queued.contains(cue.id) {
            send(cue)
        }
    }

    private func applySnapshot(_ data: Data?) {
        guard let data, let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        WatchCueStore.shared.apply(snapshot)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        let data = session.receivedApplicationContext[WatchSync.snapshotKey] as? Data
        Task { @MainActor in
            self.applySnapshot(data)
            self.sendUnqueuedPending()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchSync.snapshotKey] as? Data
        Task { @MainActor in
            self.applySnapshot(data)
        }
    }
}
