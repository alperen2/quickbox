import SwiftUI

@main
struct quickboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if let appState = appDelegate.appState {
                SettingsView(appState: appState)
            } else {
                ProgressView("Loading Settings...")
                    .frame(width: 640, height: 520)
            }
        }
    }
}
