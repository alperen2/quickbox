import AppKit
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
    private enum Layout {
        static let rowHorizontalPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 10
        static let leadingIconWidth: CGFloat = 16
        static let trailingIconWidth: CGFloat = 12
        static let minimumRowHeight: CGFloat = 44
        static let rowVerticalPadding: CGFloat = 8
        static let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let textLineHeight = ceil(textFont.ascender - textFont.descender + textFont.leading)
        static let maxTextLines: CGFloat = 3
    }

    @ObservedObject var appState: AppState
    let mode: CaptureMode
    let onClose: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var animateIn = false
    @State private var didJustSave = false
    @State private var hoveredItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(didJustSave ? Color.green : Color.accentColor)

                TextField("Capture thought...", text: $appState.draftText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .focused($isInputFocused)
                    .onSubmit {
                        submit()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
            )

            if appState.selectedInboxDateLabel != "Today" {
                Text("Saving new captures to Today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if mode == .spotlight {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 0.9)
                )
                .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 10)
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
            navButton(systemName: "chevron.left") {
                appState.navigateInboxDayBackward()
            }

            Text(appState.selectedInboxDateLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )

            navButton(systemName: "chevron.right") {
                appState.navigateInboxDayForward()
            }
            .disabled(!appState.canNavigateForwardInboxDate)

            Spacer()

            Button {
                appState.showOnlyOpenTasks.toggle()
            } label: {
                Label("Open only", systemImage: appState.showOnlyOpenTasks ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(appState.showOnlyOpenTasks ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(appState.showOnlyOpenTasks ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08))
            )

            if appState.canUndoDelete {
                Button {
                    appState.handleSpotlightMutation(.undoLastDelete)
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
            }
        }
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
                            taskRow(item)
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight)
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
            withAnimation(.easeOut(duration: 0.18)) {
                didJustSave = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.2)) {
                    didJustSave = false
                }
            }
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

        let itemsForSizing = Array(appState.visibleInboxItems.prefix(8))
        let listHeight = itemsForSizing.reduce(CGFloat.zero) { partial, item in
            partial + estimatedRowHeight(for: item)
        }
        let staticHeight: CGFloat = 170
        let totalHeight = staticHeight + max(84, listHeight)
        NotificationCenter.default.post(name: .quickboxCaptureHeightDidChange, object: totalHeight)
    }

    private var listMaxHeight: CGFloat {
        let itemsForSizing = Array(appState.visibleInboxItems.prefix(8))
        let measured = itemsForSizing.reduce(CGFloat.zero) { partial, item in
            partial + estimatedRowHeight(for: item)
        }
        return min(max(120, measured), 430)
    }

    private func estimatedRowHeight(for item: InboxItem) -> CGFloat {
        let availableTextWidth = max(
            140,
            panelWidth
            - (16 * 2)
            - (Layout.rowHorizontalPadding * 2)
            - Layout.leadingIconWidth
            - Layout.trailingIconWidth
            - (Layout.rowSpacing * 2)
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Layout.textFont,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = (item.text as NSString).boundingRect(
            with: CGSize(width: availableTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )

        let maxTextHeight = Layout.textLineHeight * Layout.maxTextLines
        let clampedTextHeight = min(max(Layout.textLineHeight, ceil(textRect.height)), maxTextHeight)
        let contentHeight = clampedTextHeight + Layout.rowVerticalPadding * 2
        return max(Layout.minimumRowHeight, contentHeight)
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ item: InboxItem) -> some View {
        HStack(spacing: 10) {
            Button {
                appState.handleSpotlightMutation(.toggle(item.id))
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appState.handleSpotlightMutation(.delete(item.id))
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .opacity(hoveredItemID == item.id ? 1 : 0.35)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hoveredItemID == item.id ? 0.12 : 0.07))
        )
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : nil
        }
    }
}
