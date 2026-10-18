import SwiftUI

@main
struct CueWatchApp: App {
    init() {
        WatchCueStore.shared.load()
        PhoneConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .backgroundTask(.watchConnectivity) {
            await PhoneConnector.shared.receivePendingContent()
        }
    }
}
