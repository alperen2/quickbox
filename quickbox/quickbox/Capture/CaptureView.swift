import SwiftUI

extension Notification.Name {
    static let quickboxFocusCapture = Notification.Name("quickbox.focusCapture")
    static let quickboxCapturePresented = Notification.Name("quickbox.capturePresented")
    static let quickboxCaptureHeightDidChange = Notification.Name("quickbox.captureHeightDidChange")
}

enum CaptureMode {
    case spotlight
    case minimal
}

struct CaptureView: View {
    @ObservedObject var appState: AppState
    let mode: CaptureMode
    let onClose: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var animateIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Capture thought...", text: $appState.draftText)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .focused($isInputFocused)
                .onSubmit {
                    submit()
                }

            if appState.selectedInboxDateLabel != "Today" {
                Text("Saving new captures to Today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if mode == .spotlight {
                spotlightActions
                spotlightHeader
                Divider().opacity(0.5)
                spotlightList
            }

            if let message = appState.captureMessage ?? appState.inboxMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        )
        .scaleEffect(animateIn ? 1.0 : 0.97)
        .offset(y: animateIn ? 0 : -10)
        .opacity(animateIn ? 1.0 : 0.0)
        .onAppear {
            animateIn = false
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                animateIn = true
            }
            isInputFocused = true
            notifyHeightChange()
        }
        .onChange(of: appState.visibleInboxItems.count) { _ in
            notifyHeightChange()
        }
        .onChange(of: appState.showOnlyOpenTasks) { _ in
            notifyHeightChange()
        }
        .onChange(of: appState.selectedInboxDate) { _ in
            notifyHeightChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickboxFocusCapture)) { _ in
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickboxCapturePresented)) { _ in
            animateIn = false
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                animateIn = true
            }
            notifyHeightChange()
        }
        .onExitCommand {
            onClose()
        }
    }

    private var panelWidth: CGFloat {
        mode == .spotlight ? 620 : 520
    }

    private var spotlightHeader: some View {
        HStack {
            Button("<") {
                appState.navigateInboxDayBackward()
            }
            .buttonStyle(.plain)
            .font(.headline)

            Text(appState.selectedInboxDateLabel)
                .font(.headline)

            Button(">") {
                appState.navigateInboxDayForward()
            }
            .buttonStyle(.plain)
            .font(.headline)
            .disabled(!appState.canNavigateForwardInboxDate)

            Spacer()

            if appState.canUndoDelete {
                Button("Undo") {
                    appState.handleSpotlightMutation(.undoLastDelete)
                }
                .font(.footnote)
            }
        }
    }

    private var spotlightActions: some View {
        HStack(spacing: 10) {
            Spacer()
            Toggle("Open only", isOn: $appState.showOnlyOpenTasks)
                .toggleStyle(.switch)
                .font(.footnote)
        }
        .font(.footnote)
    }

    private var spotlightList: some View {
        Group {
            if appState.visibleInboxItems.isEmpty {
                Text(appState.inboxMessage ?? "No notes for today yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.visibleInboxItems) { item in
                            HStack(spacing: 8) {
                                Button {
                                    appState.handleSpotlightMutation(.toggle(item.id))
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                }
                                .buttonStyle(.plain)

                                Text("\(item.time) · \(item.text)")
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    appState.handleSpotlightMutation(.delete(item.id))
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func submit() {
        let result: AppState.SubmitResult
        if mode == .spotlight {
            result = appState.submitCaptureFromSpotlight()
        } else {
            result = appState.submitCapture()
        }

        switch result {
        case .savedAndClose:
            onClose()
        case .savedKeepOpen:
            DispatchQueue.main.async {
                isInputFocused = true
            }
        case .failed:
            break
        }
    }

    private func notifyHeightChange() {
        guard mode == .spotlight else {
            return
        }

        let visibleRows = max(1, min(appState.visibleInboxItems.count, 8))
        let rowHeight: CGFloat = 28
        let staticHeight: CGFloat = 170
        let totalHeight = staticHeight + (CGFloat(visibleRows) * rowHeight)
        NotificationCenter.default.post(name: .quickboxCaptureHeightDidChange, object: totalHeight)
    }
}
