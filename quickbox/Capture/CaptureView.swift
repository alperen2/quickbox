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
    private enum FocusTarget: Hashable {
        case capture
        case rowEditor
    }

    private enum Layout {
        static let sectionGap: CGFloat = 14
        static let outerPadding: CGFloat = 10
        static let cardCornerRadius: CGFloat = 18
        static let cardPaddingHorizontal: CGFloat = 16
        static let cardPaddingVertical: CGFloat = 14
        static let rowHorizontalPadding: CGFloat = 12
        static let rowSpacing: CGFloat = 10
        static let leadingIconWidth: CGFloat = 16
        static let trailingIconWidth: CGFloat = 44
        static let actionButtonWidth: CGFloat = 30
        static let actionGap: CGFloat = 6
        static let minimumRowHeight: CGFloat = 58
        static let rowVerticalPadding: CGFloat = 6
        static let rowSeparatorHeight: CGFloat = 1
        static let rowSeparatorVerticalPadding: CGFloat = 0
        static let textFont = NSFont.systemFont(ofSize: 14, weight: .medium)
        static let textLineHeight = ceil(textFont.ascender - textFont.descender + textFont.leading)
        static let maxTextLines: CGFloat = 3
    }

    @ObservedObject var appState: AppState
    let mode: CaptureMode
    let onClose: () -> Void

    @FocusState private var focusedField: FocusTarget?
    @State private var animateIn = false
    @State private var hoveredItemID: String?
    @State private var editingItemID: String?
    @State private var editingDraftText: String = ""
    
    // Autocomplete State
    @State private var autocompleteType: AutocompleteType = .none
    @State private var autocompleteSuggestions: [String] = []
    @State private var autocompleteSelectedIndex: Int = 0
    @State private var availableTags: [String] = []
    @State private var availableProjects: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: mode == .spotlight ? Layout.sectionGap : 0) {
            captureSection

            if mode == .spotlight {
                spotlightSection
            }
        }
        .padding(Layout.outerPadding)
        .frame(width: panelWidth)
        .background(Color.clear)
        .preferredColorScheme(mode == .spotlight ? .dark : nil)
        .scaleEffect(animateIn ? 1.0 : 0.97)
        .offset(y: animateIn ? 0 : -10)
        .opacity(animateIn ? 1.0 : 0.0)
        .onAppear {
            animateIn = false
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                animateIn = true
            }
            focusedField = .capture
            notifyHeightChange()
        }
        .onReceive(IndexManager.shared.tagsPublisher) { tags in
            self.availableTags = tags
        }
        .onReceive(IndexManager.shared.projectsPublisher) { projects in
            self.availableProjects = projects
        }
        .onChange(of: appState.visibleInboxItems.count) {
            notifyHeightChange()
        }
        .onChange(of: appState.showOnlyOpenTasks) {
            notifyHeightChange()
        }
        .onChange(of: appState.selectedInboxDate) {
            notifyHeightChange()
        }
        .onChange(of: appState.draftText) {
            handleTextChange(appState.draftText)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickboxFocusCapture)) { _ in
            DispatchQueue.main.async {
                focusedField = .capture
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
            if editingItemID != nil {
                cancelEditing()
            } else if case .none = autocompleteType {
                onClose()
            } else {
                closeAutocomplete()
            }
        }
    }

    private var panelWidth: CGFloat {
        mode == .spotlight ? 620 : 520
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.66))

                CustomTextFieldWithKeyHandling(
                    text: $appState.draftText,
                    prompt: "Capture thought...",
                    onUpArrow: {
                        if !autocompleteSuggestions.isEmpty {
                            autocompleteSelectedIndex = max(0, autocompleteSelectedIndex - 1)
                            return true
                        }
                        return false
                    },
                    onDownArrow: {
                        if !autocompleteSuggestions.isEmpty {
                            autocompleteSelectedIndex = min(autocompleteSuggestions.count - 1, autocompleteSelectedIndex + 1)
                            return true
                        }
                        return false
                    },
                    onEnter: {
                        if !autocompleteSuggestions.isEmpty {
                            acceptAutocomplete()
                            return true
                        }
                        return false
                    },
                    onTab: {
                        if !autocompleteSuggestions.isEmpty {
                            acceptAutocomplete()
                            return true
                        }
                        return false
                    },
                    onSubmit: {
                        if autocompleteSuggestions.isEmpty {
                            submit()
                        }
                    }
                )
                .focused($focusedField, equals: .capture)
            }
            .overlay(alignment: .bottomLeading) {
                if !autocompleteSuggestions.isEmpty {
                    AutocompleteMenu(
                        mode: autocompleteType,
                        suggestions: autocompleteSuggestions,
                        selectedIndex: autocompleteSelectedIndex
                    )
                    .alignmentGuide(.bottom) { d in d[.top] + 8 }
                    .alignmentGuide(.leading) { d in d[.leading] + 28 } // Align roughly under text start
                }
            }
        }
        .padding(.horizontal, Layout.cardPaddingHorizontal)
        .padding(.vertical, Layout.cardPaddingVertical)
        .background(cardBackground())
    }
    
    // MARK: - Autocomplete Logic
    private func handleTextChange(_ newText: String) {
        // Quick extraction to see what word the cursor is currently on.
        // For simplicity in SwiftUI textfield, we'll look at the last word typed.
        guard let lastWord = newText.components(separatedBy: .whitespaces).last, !lastWord.isEmpty else {
            closeAutocomplete()
            return
        }
        
        let prefix = String(lastWord.prefix(1))
        let query = String(lastWord.dropFirst()).lowercased()
        
        if prefix == "#" && query.isEmpty {
            autocompleteType = .tag(query: "")
            autocompleteSuggestions = Array(availableTags.prefix(5))
            autocompleteSelectedIndex = 0
            return
        } else if prefix == "#" {
            autocompleteType = .tag(query: query)
            let matches = availableTags.filter { $0.lowercased().hasPrefix(query) }
            autocompleteSuggestions = Array(matches.prefix(5))
            autocompleteSelectedIndex = 0
            if autocompleteSuggestions.isEmpty { closeAutocomplete() }
            return
        }
        
        if prefix == "@" && query.isEmpty {
            autocompleteType = .project(query: "")
            autocompleteSuggestions = Array(availableProjects.prefix(5))
            autocompleteSelectedIndex = 0
            return
        } else if prefix == "@" {
            autocompleteType = .project(query: query)
            let matches = availableProjects.filter { $0.lowercased().hasPrefix(query) }
            autocompleteSuggestions = Array(matches.prefix(5))
            autocompleteSelectedIndex = 0
            if autocompleteSuggestions.isEmpty { closeAutocomplete() }
            return
        }
        
        if lastWord.contains(":") && !lastWord.lowercased().hasPrefix("http") {
             let parts = lastWord.components(separatedBy: ":")
             if parts.count >= 2 {
                 let key = parts[0].lowercased()
                 let valQuery = parts.dropFirst().joined(separator: ":").lowercased()

                 let dateOptions = ["tdy", "tmr", "tmrw", "nw", "eow", "eom"]
                 let timeOptions = ["15m", "30m", "45m", "1h", "2h", "1d"]
                 let reminderOptions = ["15m", "30m", "1h", "1d"]
                 
                 let options: [String]
                 switch key {
                 case "due", "defer", "start": options = dateOptions
                 case "time", "dur", "duration": options = timeOptions
                 case "remind", "alarm": options = reminderOptions
                 default: options = []
                 }
                 
                 if !options.isEmpty {
                     autocompleteType = .metadata(key: key, query: valQuery)
                     let matches = valQuery.isEmpty ? options : options.filter { $0.hasPrefix(valQuery) }
                     autocompleteSuggestions = Array(matches.prefix(5))
                     autocompleteSelectedIndex = 0
                     if autocompleteSuggestions.isEmpty { closeAutocomplete() }
                     return
                 }
             }
        }
        
        closeAutocomplete()
    }
    
    private func closeAutocomplete() {
        autocompleteType = .none
        autocompleteSuggestions = []
        autocompleteSelectedIndex = 0
    }
    
    private func acceptAutocomplete() {
        guard autocompleteSuggestions.indices.contains(autocompleteSelectedIndex) else { return }
        let accepted = autocompleteSuggestions[autocompleteSelectedIndex]
        
        // Replace the last typed keyword with the accepted suggestion
        var components = appState.draftText.components(separatedBy: .whitespaces)
        guard !components.isEmpty else { return }
        
        let prefix: String
        switch autocompleteType {
        case .tag: prefix = "#"
        case .project: prefix = "@"
        case .metadata(let key, _): prefix = "\(key):"
        default: prefix = ""
        }
        
        components[components.count - 1] = "\(prefix)\(accepted) "
        appState.draftText = components.joined(separator: " ")
        closeAutocomplete()
    }

    private var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            spotlightHeader
            spotlightList

            if let message = appState.captureMessage ?? appState.inboxMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Layout.cardPaddingHorizontal)
        .padding(.vertical, Layout.cardPaddingVertical)
        .background(cardBackground())
    }

    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.34))
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
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
                    .foregroundStyle(appState.showOnlyOpenTasks ? Color.white.opacity(0.95) : Color.white.opacity(0.68))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(appState.showOnlyOpenTasks ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
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
                    let items = Array(appState.visibleInboxItems.enumerated())
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.element.id) { index, item in
                            taskRow(item)
                            if index < items.count - 1 {
                                taskSeparator
                            }
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
            DispatchQueue.main.async {
                focusedField = .capture
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
        let rowsHeight = itemsForSizing.reduce(CGFloat.zero) { partial, item in
            partial + estimatedRowHeight(for: item)
        }
        let separators = CGFloat(max(itemsForSizing.count - 1, 0))
        let separatorsHeight = separators * (Layout.rowSeparatorHeight + (Layout.rowSeparatorVerticalPadding * 2))
        let listHeight = rowsHeight + separatorsHeight
        let staticHeight: CGFloat = 140
        let totalHeight = staticHeight + max(84, listHeight)
        NotificationCenter.default.post(name: .quickboxCaptureHeightDidChange, object: totalHeight)
    }

    private var listMaxHeight: CGFloat {
        let itemsForSizing = Array(appState.visibleInboxItems.prefix(8))
        let rowsHeight = itemsForSizing.reduce(CGFloat.zero) { partial, item in
            partial + estimatedRowHeight(for: item)
        }
        let separators = CGFloat(max(itemsForSizing.count - 1, 0))
        let separatorsHeight = separators * (Layout.rowSeparatorHeight + (Layout.rowSeparatorVerticalPadding * 2))
        let measured = rowsHeight + separatorsHeight
        return min(max(120, measured), 430)
    }

    private func estimatedRowHeight(for item: InboxItem) -> CGFloat {
        let availableTextWidth = max(
            140,
            panelWidth
            - (16 * 2)
            - (Layout.rowHorizontalPadding * 2)
            - (Layout.actionButtonWidth * 2)
            - (Layout.actionGap * 2)
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
        let isEditing = editingItemID == item.id
        let isHovered = hoveredItemID == item.id
        let rowHeight = estimatedRowHeight(for: item)

        return HStack(spacing: Layout.actionGap) {
            HStack(spacing: Layout.rowSpacing) {
                Button {
                    appState.handleSpotlightMutation(.toggle(item.id))
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.isCompleted ? Color.white.opacity(0.95) : priorityColor(for: item.priority))
                }
                .buttonStyle(.plain)
                .disabled(isEditing)

                HStack(alignment: .top, spacing: 8) {
                    if isEditing {
                        TextField("Edit task", text: $editingDraftText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .focused($focusedField, equals: .rowEditor)
                            .onSubmit {
                                saveEditing(item)
                            }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .font(.system(size: 14, weight: .medium))
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                
                            if !item.tags.isEmpty || item.projectName != nil || !item.metadata.isEmpty {
                                HStack(spacing: 6) {
                                    if let project = item.projectName {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                            Text(project)
                                        }
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(4)
                                        .foregroundStyle(Color.white.opacity(0.85))
                                    }
                                    
                                    ForEach(item.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                            .foregroundStyle(.blue)
                                    }
                                    
                                    ForEach(item.metadata.keys.sorted(), id: \.self) { key in
                                        if let val = item.metadata[key] {
                                            HStack(spacing: 4) {
                                                Image(systemName: iconForMetadataKey(key))
                                                Text("\(key):\(val)")
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.2))
                                            .cornerRadius(4)
                                            .foregroundStyle(.purple)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    Text(item.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Layout.rowHorizontalPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                startEditing(item)
            }

            if isEditing {
                sideActionButton(
                    tooltip: "Save",
                    systemImage: "checkmark",
                    tint: Color.green.opacity(0.9)
                ) {
                    saveEditing(item)
                }

                sideActionButton(
                    tooltip: "Cancel",
                    systemImage: "xmark",
                    tint: Color.white.opacity(0.72)
                ) {
                    cancelEditing()
                }
            } else {
                sideActionButton(
                    tooltip: "Edit",
                    systemImage: "pencil",
                    tint: Color.white.opacity(0.85)
                ) {
                    startEditing(item)
                }
                .opacity(isHovered ? 1 : 0.86)

                sideActionButton(
                    tooltip: "Delete",
                    systemImage: "trash",
                    tint: isHovered ? Color.red.opacity(0.9) : Color.white.opacity(0.85)
                ) {
                    appState.handleSpotlightMutation(.delete(item.id))
                }
                .opacity(isHovered ? 1 : 0.86)
            }
        }
        .onHover { hovering in
            if !isEditing {
                hoveredItemID = hovering ? item.id : nil
            }
        }
    }

    private var taskSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: Layout.rowSeparatorHeight)
            .padding(.vertical, Layout.rowSeparatorVerticalPadding)
            .padding(.leading, Layout.rowHorizontalPadding + Layout.leadingIconWidth + Layout.rowSpacing)
            .padding(.trailing, (Layout.actionButtonWidth * 2) + (Layout.actionGap * 2))
    }

    private func sideActionButton(
        tooltip: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func startEditing(_ item: InboxItem) {
        editingItemID = item.id
        editingDraftText = item.text
        focusRowEditorWithoutSelectingAll()
    }

    private func cancelEditing() {
        editingItemID = nil
        editingDraftText = ""
        focusedField = .capture
    }

    private func saveEditing(_ item: InboxItem) {
        let cleaned = editingDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != item.text else {
            cancelEditing()
            return
        }

        if appState.editInboxItem(id: item.id, text: cleaned) {
            cancelEditing()
        }
    }

    private func focusRowEditorWithoutSelectingAll() {
        DispatchQueue.main.async {
            focusedField = .rowEditor
            DispatchQueue.main.async {
                guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                    return
                }
                let end = textView.string.count
            }
        }
    }

    private func priorityColor(for priority: Int?) -> Color {
        guard let priority = priority else { return Color.white.opacity(0.62) }
        switch priority {
        case 1: return Color.red.opacity(0.85)
        case 2: return Color.orange.opacity(0.85)
        case 3: return Color.blue.opacity(0.85)
        default: return Color.white.opacity(0.62)
        }
    }
    
    // MARK: - Helpers
    private func iconForMetadataKey(_ key: String) -> String {
        switch key.lowercased() {
        case "dur", "time", "duration": return "clock"
        case "defer", "start": return "hourglass.bottomhalf.filled"
        case "remind", "alarm": return "bell.fill"
        default: return "tag"
        }
    }
}
