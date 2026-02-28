import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("quickbox")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Open Today File") {
                    appState.openTodayFile()
                }
                Button("Open Inbox Folder") {
                    appState.openInboxFolder()
                }
            }
            .font(.footnote)

            Button("Check for Updates") {
                appState.checkForUpdates()
            }
            .font(.footnote)

            Divider()

            HStack {
                Button("Settings", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
            }
            .font(.footnote)

            if let message = appState.inboxMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
