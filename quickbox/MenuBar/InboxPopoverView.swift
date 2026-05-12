import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var appState: AppState
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("quickbox")
                    .font(.headline)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            HStack(spacing: 4) {
                Button {
                    appState.openTodayFile()
                } label: {
                    Label("Open today", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    appState.openInboxFolder()
                } label: {
                    Label("Open folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .controlSize(.small)

            Divider()

            VStack(spacing: 2) {
                PopoverMenuRow(title: "Settings", systemImage: "gearshape", action: onOpenSettings)
                PopoverMenuRow(title: "Quit quickbox", systemImage: "power", action: onQuit)
            }

            if let message = appState.inboxMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(width: 280)
        .background(.regularMaterial)
    }

    private var statusText: String {
        let count = appState.inboxItems.count
        return count == 1 ? "1 today" : "\(count) today"
    }

}

private struct PopoverMenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isHovered ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
