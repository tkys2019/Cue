import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Defaults to ON. When OFF, the Info.plist orientations apply.
        let locked = UserDefaults.standard.object(forKey: "lockPortraitOrientation") as? Bool ?? true
        return locked ? .portrait : .all
    }
}

@main
struct CueiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
