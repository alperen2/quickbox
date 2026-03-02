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
    @State private var isCalendarViewActive: Bool = false
    @State private var calendarMonthAnchor: Date = Calendar(identifier: .gregorian).startOfDay(for: Date())

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
            if isCalendarViewActive && !isSameMonth(appState.selectedInboxDate, calendarMonthAnchor) {
                calendarMonthAnchor = appState.selectedInboxDate
            }
            notifyHeightChange()
        }
        .onChange(of: appState.draftText) {
            handleTextChange(appState.draftText)
        }
        .onChange(of: isCalendarViewActive) {
            notifyHeightChange()
            if isCalendarViewActive {
                calendarMonthAnchor = appState.selectedInboxDate
                refreshCalendarIndicators()
            } else {
                DispatchQueue.main.async {
                    focusedField = .capture
                }
            }
        }
        .onChange(of: calendarMonthAnchor) {
            guard isCalendarViewActive else {
                return
            }
            refreshCalendarIndicators()
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
            if isCalendarViewActive {
                closeCalendarView()
            } else if editingItemID != nil {
                cancelEditing()
            } else if case .none = autocompleteType {
                onClose()
            } else {
                closeAutocomplete()
            }
        }
    }

    private var panelWidth: CGFloat {
        if mode == .spotlight {
            return isCalendarViewActive ? 760 : 620
        }
        return 520
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

                if mode == .spotlight {
                    calendarModeButton
                }
            }
            .overlay(alignment: .topLeading) {
                if !autocompleteSuggestions.isEmpty {
                    AutocompleteMenu(
                        mode: autocompleteType,
                        suggestions: autocompleteSuggestions,
                        selectedIndex: autocompleteSelectedIndex
                    )
                    .offset(x: 28, y: 40) // below input, absolute overlay
                    .zIndex(30)
                }
            }
        }
        .padding(.horizontal, Layout.cardPaddingHorizontal)
        .padding(.vertical, Layout.cardPaddingVertical)
        .background(cardBackground())
        .zIndex(autocompleteSuggestions.isEmpty ? 1 : 20)
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
            autocompleteSuggestions = availableTags
            autocompleteSelectedIndex = 0
            return
        } else if prefix == "#" {
            autocompleteType = .tag(query: query)
            let matches = availableTags.filter { $0.lowercased().hasPrefix(query) }
            autocompleteSuggestions = matches
            autocompleteSelectedIndex = 0
            if autocompleteSuggestions.isEmpty { closeAutocomplete() }
            return
        }
        
        if prefix == "@" && query.isEmpty {
            autocompleteType = .project(query: "")
            autocompleteSuggestions = availableProjects
            autocompleteSelectedIndex = 0
            return
        } else if prefix == "@" {
            autocompleteType = .project(query: query)
            let matches = availableProjects.filter { $0.lowercased().hasPrefix(query) }
            autocompleteSuggestions = matches
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
                     autocompleteSuggestions = matches
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
            if isCalendarViewActive {
                spotlightCalendar
            } else {
                spotlightHeader
                spotlightList
            }

            if let message = appState.captureMessage ?? appState.inboxMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Layout.cardPaddingHorizontal)
        .padding(.vertical, Layout.cardPaddingVertical)
        .background(cardBackground())
        .zIndex(1)
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

    private var calendarModeButton: some View {
        Button {
            closeAutocomplete()
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                isCalendarViewActive.toggle()
            }
        } label: {
            Image(systemName: isCalendarViewActive ? "calendar.circle.fill" : "calendar.circle")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(isCalendarViewActive ? Color.white.opacity(0.95) : Color.white.opacity(0.78))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isCalendarViewActive ? Color.white.opacity(0.18) : Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isCalendarViewActive ? 0.34 : 0.14), lineWidth: 0.9)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendar view")
        .help("Open calendar")
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

    private var spotlightCalendar: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.10))
                        )
                    Text("Calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Text(appState.selectedInboxDateLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    Spacer()
                    Button {
                        closeCalendarView()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                }

                HStack(spacing: 6) {
                    calendarJumpButton(title: "Today", systemName: "sun.max") {
                        appState.selectInboxDate(Date())
                    }
                    calendarJumpButton(title: "-1W", systemName: "chevron.left.2") {
                        shiftInboxDate(days: -7)
                    }
                    calendarJumpButton(title: "+1W", systemName: "chevron.right.2") {
                        shiftInboxDate(days: 7)
                    }
                    calendarJumpButton(title: "-1M", systemName: "arrow.left.to.line") {
                        shiftInboxDate(months: -1)
                    }
                    calendarJumpButton(title: "+1M", systemName: "arrow.right.to.line") {
                        shiftInboxDate(months: 1)
                    }
                }

                VStack(spacing: 8) {
                    HStack {
                        Button {
                            shiftCalendarMonth(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.86))

                        Spacer()

                        Text(calendarMonthTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.92))

                        Spacer()

                        Button {
                            shiftCalendarMonth(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.86))
                    }
                    .padding(.horizontal, 8)

                    HStack(spacing: 0) {
                        ForEach(Array(calendarWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 4)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(minimum: 34, maximum: 120), spacing: 6), count: 7),
                        spacing: 8
                    ) {
                        ForEach(calendarVisibleDates, id: \.self) { date in
                            calendarDayCell(for: date)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            calendarSidebar
        }
    }

    private var calendarSidebar: some View {
        let totalCount = appState.inboxItems.count
        let openCount = appState.inboxItems.filter { !$0.isCompleted }.count
        let completedCount = totalCount - openCount

        return VStack(alignment: .leading, spacing: 10) {
            Text("Quick Jump")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))

            calendarSidebarButton("Yesterday", systemName: "arrow.left") {
                shiftInboxDate(days: -1)
            }
            calendarSidebarButton("Tomorrow", systemName: "arrow.right") {
                shiftInboxDate(days: 1)
            }
            calendarSidebarButton("Next Month", systemName: "calendar.badge.plus") {
                shiftInboxDate(months: 1)
            }
            calendarSidebarButton("Prev Month", systemName: "calendar.badge.minus") {
                shiftInboxDate(months: -1)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            Text("Selected Day")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.88))
            Text(appState.selectedInboxDateLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.95))

            HStack {
                Label("\(openCount) open", systemImage: "circle")
                    .foregroundStyle(Color.white.opacity(0.80))
                Spacer()
            }
            .font(.caption)

            HStack {
                Label("\(completedCount) done", systemImage: "checkmark.circle")
                    .foregroundStyle(Color.white.opacity(0.72))
                Spacer()
            }
            .font(.caption)

            HStack {
                Label("\(totalCount) total", systemImage: "number")
                    .foregroundStyle(Color.white.opacity(0.66))
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var calendarMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: startOfMonth(for: calendarMonthAnchor))
    }

    private var calendarWeekdaySymbols: [String] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let source = formatter.shortStandaloneWeekdaySymbols
            ?? formatter.shortWeekdaySymbols
            ?? ["S", "M", "T", "W", "T", "F", "S"]
        let firstIndex = max(0, calendar.firstWeekday - 1)
        return (0..<source.count).map { index in
            source[(firstIndex + index) % source.count]
        }
    }

    private var calendarVisibleDates: [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = startOfMonth(for: calendarMonthAnchor)
        let firstWeekdayInMonth = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekdayInMonth - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) else {
            return []
        }
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    private func calendarDayCell(for date: Date) -> some View {
        let dayNumber = Calendar(identifier: .gregorian).component(.day, from: date)
        let isSelected = isSameDay(date, appState.selectedInboxDate)
        let isCurrentMonth = isSameMonth(date, calendarMonthAnchor)
        let isToday = isSameDay(date, Date())
        let dotColors = calendarDotColors(for: date)

        return Button {
            appState.selectInboxDate(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.caption.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(
                        isSelected
                        ? Color.black.opacity(0.86)
                        : (isCurrentMonth ? Color.white.opacity(0.92) : Color.white.opacity(0.38))
                    )
                    .frame(maxWidth: .infinity)

                HStack(spacing: 3) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                        ? Color.white.opacity(0.92)
                        : (isToday ? Color.white.opacity(0.16) : Color.white.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isToday && !isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func calendarDotColors(for date: Date) -> [Color] {
        let normalized = Calendar(identifier: .gregorian).startOfDay(for: date)
        guard let indicator = appState.calendarDayIndicators[normalized] else {
            return []
        }

        var colors: [Color] = []
        if indicator.priorities.contains(1) {
            colors.append(Color.red.opacity(0.92))
        }
        if indicator.priorities.contains(2) {
            colors.append(Color.orange.opacity(0.92))
        }
        if indicator.priorities.contains(3) {
            colors.append(Color.blue.opacity(0.92))
        }
        if indicator.hasUnprioritized {
            colors.append(Color.white.opacity(0.45))
        }
        return Array(colors.prefix(4))
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

        if isCalendarViewActive {
            NotificationCenter.default.post(name: .quickboxCaptureHeightDidChange, object: CGFloat(600))
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

    private func calendarJumpButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
        }
        .buttonStyle(.plain)
    }

    private func calendarSidebarButton(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .foregroundStyle(Color.white.opacity(0.84))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
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
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if item.metadata["defer"] != nil || item.metadata["start"] != nil {
                                    Image(systemName: "tray.and.arrow.down.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.blue.opacity(0.8))
                                        .help("Deferred Arrival")
                                }
                                
                                Text(item.text)
                                    .font(.system(size: 14, weight: .medium))
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                                
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
                                            Menu {
                                                if key == "dur" || key == "time" || key == "duration" {
                                                    Button("15m") { updateMetadata(item: item, key: key, newValue: "15m") }
                                                    Button("30m") { updateMetadata(item: item, key: key, newValue: "30m") }
                                                    Button("1h") { updateMetadata(item: item, key: key, newValue: "1h") }
                                                    Divider()
                                                    Button("Remove") { updateMetadata(item: item, key: key, newValue: nil) }
                                                } else if key == "remind" || key == "alarm" {
                                                    Button("15m") { updateMetadata(item: item, key: key, newValue: "15m") }
                                                    Button("1h") { updateMetadata(item: item, key: key, newValue: "1h") }
                                                    Button("1d") { updateMetadata(item: item, key: key, newValue: "1d") }
                                                    Divider()
                                                    Button("Remove") { updateMetadata(item: item, key: key, newValue: nil) }
                                                } else if key == "defer" || key == "due" || key == "start" {
                                                    Button("Today") { updateMetadata(item: item, key: key, newValue: "tdy") }
                                                    Button("Tomorrow") { updateMetadata(item: item, key: key, newValue: "tmr") }
                                                    Button("Next Week") { updateMetadata(item: item, key: key, newValue: "nw") }
                                                    Divider()
                                                    Button("Remove") { updateMetadata(item: item, key: key, newValue: nil) }
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: iconForMetadataKey(key))
                                                    Text("\(key):\(val)")
                                                }
                                                .font(.system(size: 11, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(colorForMetadataKey(key).opacity(0.2))
                                                .cornerRadius(4)
                                                .foregroundStyle(colorForMetadataKey(key))
                                            }
                                            .menuStyle(.borderlessButton)
                                            .fixedSize()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 6)

                    Text(plannedTimeDisplay(for: item))
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
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }
    }

    private func closeCalendarView() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
            isCalendarViewActive = false
        }
    }

    private func refreshCalendarIndicators() {
        guard let first = calendarVisibleDates.first,
              let last = calendarVisibleDates.last else {
            return
        }
        appState.loadCalendarIndicators(from: first, to: last)
    }

    private func shiftCalendarMonth(by value: Int) {
        let calendar = Calendar(identifier: .gregorian)
        guard let shifted = calendar.date(byAdding: .month, value: value, to: calendarMonthAnchor) else {
            return
        }
        calendarMonthAnchor = startOfMonth(for: shifted)
    }

    private func shiftInboxDate(days: Int) {
        let calendar = Calendar(identifier: .gregorian)
        guard let shifted = calendar.date(byAdding: .day, value: days, to: appState.selectedInboxDate) else {
            return
        }
        appState.selectInboxDate(shifted)
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar(identifier: .gregorian).isDate(lhs, inSameDayAs: rhs)
    }

    private func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let lhsComps = calendar.dateComponents([.year, .month], from: lhs)
        let rhsComps = calendar.dateComponents([.year, .month], from: rhs)
        return lhsComps.year == rhsComps.year && lhsComps.month == rhsComps.month
    }

    private func shiftInboxDate(months: Int) {
        let calendar = Calendar(identifier: .gregorian)
        guard let shifted = calendar.date(byAdding: .month, value: months, to: appState.selectedInboxDate) else {
            return
        }
        appState.selectInboxDate(shifted)
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
    private func plannedTimeDisplay(for item: InboxItem) -> String {
        guard let durStr = item.metadata["dur"] ?? item.metadata["time"] ?? item.metadata["duration"] else {
            return item.time
        }
        
        var minutesToAdd = 0
        if durStr.hasSuffix("m"), let val = Int(durStr.dropLast()) {
            minutesToAdd = val
        } else if durStr.hasSuffix("h"), let val = Int(durStr.dropLast()) {
            minutesToAdd = val * 60
        } else if durStr.hasSuffix("d"), let val = Int(durStr.dropLast()) {
            minutesToAdd = val * 24 * 60
        } else {
            return item.time
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let startTime = formatter.date(from: item.time),
              let endTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: startTime) else {
            return item.time
        }
        
        return "\(item.time) - \(formatter.string(from: endTime))"
    }
    
    private func iconForMetadataKey(_ key: String) -> String {
        switch key.lowercased() {
        case "dur", "time", "duration": return "clock"
        case "defer", "start": return "hourglass.bottomhalf.filled"
        case "remind", "alarm": return "bell.fill"
        default: return "tag"
        }
    }
    
    private func colorForMetadataKey(_ key: String) -> Color {
        switch key.lowercased() {
        case "dur", "time", "duration": return .gray
        case "defer", "start": return .blue
        case "remind", "alarm": return .orange
        default: return .purple
        }
    }
    
    private func updateMetadata(item: InboxItem, key: String, newValue: String?) {
        guard let oldVal = item.metadata[key] else { return }
        let oldString = "\(key):\(oldVal)"
        var newText = item.rawLine
        
        if let newVal = newValue {
            let newString = "\(key):\(newVal)"
            newText = newText.replacingOccurrences(of: oldString, with: newString)
        } else {
            newText = newText.replacingOccurrences(of: " " + oldString, with: "")
            newText = newText.replacingOccurrences(of: oldString, with: "")
        }
        
        newText = newText.trimmingCharacters(in: .whitespaces)
        appState.handleSpotlightMutation(.edit(item.id, text: newText))
    }
}
