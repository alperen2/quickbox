import SwiftUI

enum AutocompleteType {
    case none
    case tag(query: String)
    case project(query: String)
    case priority(query: String)
    case metadataKey(query: String)
    case metadata(key: String, query: String)
}

struct AutocompleteMenu: View {
    let mode: AutocompleteType
    let suggestions: [String]
    let selectedIndex: Int
    var onSelectIndex: (Int) -> Void = { _ in }
    var onAcceptSuggestion: (Int) -> Void = { _ in }

    private let menuWidth: CGFloat = 380
    private let menuMaxHeight: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)

            Divider()
                .overlay(Color.white.opacity(0.12))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    suggestionsList
                }
                .frame(height: menuContentHeight)
                .onAppear {
                    guard !suggestions.isEmpty else {
                        return
                    }
                    proxy.scrollTo(clampedSelectedIndex, anchor: .center)
                }
                .onChange(of: selectedIndex) {
                    guard !suggestions.isEmpty else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(clampedSelectedIndex, anchor: .center)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.12))

            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(width: menuWidth, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 11)
                .shadow(color: Color.black.opacity(0.24), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.52), lineWidth: 1.2)
        )
        .compositingGroup()
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
        .accessibilityIdentifier("capture-autocomplete-menu")
    }

    private var clampedSelectedIndex: Int {
        guard !suggestions.isEmpty else {
            return 0
        }
        return min(max(selectedIndex, 0), suggestions.count - 1)
    }

    private var menuContentHeight: CGFloat {
        if suggestions.isEmpty {
            return 56
        }
        return min(menuMaxHeight, CGFloat(suggestions.count) * 34 + 12)
    }

    @ViewBuilder
    private var suggestionsList: some View {
        if suggestions.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                    Button {
                        onAcceptSuggestion(index)
                    } label: {
                        HStack(spacing: 6) {
                            icon(for: mode)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(iconColor(for: mode))

                            Text(item)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(index == selectedIndex ? .white : Color.white.opacity(0.92))

                            if let previewStr = preview(for: mode, item: item) {
                                Text(previewStr)
                                    .font(.system(size: 11))
                                    .foregroundColor(index == selectedIndex ? Color.white.opacity(0.76) : Color.white.opacity(0.58))
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(index == selectedIndex ? Color.accentColor.opacity(0.96) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .padding(.horizontal, 3)
                    }
                    .buttonStyle(.plain)
                    .id(index)
                    .onHover { hovering in
                        if hovering {
                            onSelectIndex(index)
                        }
                    }
                    .accessibilityIdentifier("autocomplete-item-\(index)")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.56))
            Text("Öneri yok. Yazmaya devam et veya Enter ile kaydet.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.62))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityIdentifier("autocomplete-empty-state")
    }

    private var header: some View {
        HStack(spacing: 6) {
            icon(for: mode)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(iconColor(for: mode).opacity(0.95))
            Text(modeTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.white.opacity(0.78))
            Spacer()
            Text("\(suggestions.count)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.white.opacity(0.52))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.56))
            Text(suggestions.isEmpty ? "Enter: kaydet • Esc: kapat" : "↑↓: seç • Tab: tamamla • Enter: tamamla/kaydet • Esc: kapat")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.56))
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("autocomplete-footer")
    }

    @ViewBuilder
    private func icon(for mode: AutocompleteType) -> some View {
        switch mode {
        case .tag: Image(systemName: "number")
        case .project: Image(systemName: "folder.fill")
        case .priority: Image(systemName: "exclamationmark")
        case .metadataKey: Image(systemName: "slider.horizontal.3")
        case .metadata(let key, _): Image(systemName: iconForMetadataKey(key))
        case .none: EmptyView()
        }
    }

    private func iconColor(for mode: AutocompleteType) -> Color {
        switch mode {
        case .tag: return .green.opacity(0.8)
        case .project: return .purple.opacity(0.8)
        case .priority: return .orange.opacity(0.8)
        case .metadataKey: return .teal.opacity(0.9)
        case .metadata: return .blue.opacity(0.8)
        case .none: return .clear
        }
    }

    private func iconForMetadataKey(_ key: String) -> String {
        switch key.lowercased() {
        case "due": return "calendar"
        case "dur", "time", "duration": return "clock"
        case "defer", "start": return "hourglass.bottomhalf.filled"
        case "remind", "alarm": return "bell.fill"
        default: return "tag"
        }
    }

    private var modeTitle: String {
        switch mode {
        case .tag:
            return "Tag suggestions"
        case .project:
            return "Project suggestions"
        case .priority:
            return "Priority suggestions"
        case .metadataKey:
            return "Field suggestions"
        case .metadata(let key, _):
            return "\(key.uppercased()) suggestions"
        case .none:
            return "Suggestions"
        }
    }

    private func preview(for mode: AutocompleteType, item: String) -> String? {
        switch mode {
        case .priority:
            switch item {
            case "1": return "(High)"
            case "2": return "(Medium)"
            case "3": return "(Low)"
            default: return nil
            }

        case .metadataKey:
            switch item.lowercased() {
            case "due": return "(deadline)"
            case "defer", "start": return "(hide until)"
            case "dur", "time", "duration": return "(planned time)"
            case "remind", "alarm": return "(notification)"
            default: return nil
            }

        case .metadata(let key, _):
            switch key.lowercased() {
            case "due", "defer", "start":
                if let date = DeferDateResolver().resolve(deferDateString: item, from: Date()) {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "d MMM, EEE"
                    return "(\(formatter.string(from: date)))"
                }
            case "time", "dur", "duration", "remind", "alarm":
                var minutesToAdd = 0
                if item.hasSuffix("m"), let val = Int(item.dropLast()) {
                    minutesToAdd = val
                } else if item.hasSuffix("h"), let val = Int(item.dropLast()) {
                    minutesToAdd = val * 60
                } else if item.hasSuffix("d"), let val = Int(item.dropLast()) {
                    minutesToAdd = val * 24 * 60
                }
                if minutesToAdd > 0, let targetTime = Calendar.current.date(byAdding: .minute, value: minutesToAdd, to: Date()) {
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    return "(\(formatter.string(from: targetTime)))"
                }
            default: break
            }
            return nil

        default:
            return nil
        }
    }
}
