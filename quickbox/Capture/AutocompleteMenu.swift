import SwiftUI

enum AutocompleteType {
    case none
    case tag(query: String)
    case project(query: String)
    case priority(query: String)
    case metadata(key: String, query: String)
}

struct AutocompleteMenu: View {
    let mode: AutocompleteType
    let suggestions: [String]
    let selectedIndex: Int
    
    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            Group {
                if suggestions.count > 8 {
                    ScrollView(showsIndicators: false) {
                        suggestionsList
                    }
                    .frame(height: 260)
                } else {
                    suggestionsList
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    icon(for: mode)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(iconColor(for: mode))
                    
                    Text(item)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(index == selectedIndex ? .white : .primary)
                    
                    if let previewStr = preview(for: mode, item: item) {
                        Text(previewStr)
                            .font(.system(size: 11))
                            .foregroundColor(index == selectedIndex ? Color.white.opacity(0.7) : .secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(index == selectedIndex ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
                .cornerRadius(4)
            }
        }
        .padding(4)
    }
    
    @ViewBuilder
    private func icon(for mode: AutocompleteType) -> some View {
        switch mode {
        case .tag: Image(systemName: "number")
        case .project: Image(systemName: "folder.fill")
        case .priority: Image(systemName: "exclamationmark")
        case .metadata(let key, _): Image(systemName: iconForMetadataKey(key))
        case .none: EmptyView()
        }
    }
    
    private func iconColor(for mode: AutocompleteType) -> Color {
        switch mode {
        case .tag: return .green.opacity(0.8)
        case .project: return .purple.opacity(0.8)
        case .priority: return .orange.opacity(0.8)
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
    
    private func preview(for mode: AutocompleteType, item: String) -> String? {
        guard case .metadata(let key, _) = mode else { return nil }
        
        switch key.lowercased() {
        case "due", "defer", "start":
            // DeferDateResolver allows reusing the existing smart date logic
            if let date = DeferDateResolver().resolve(deferDateString: item, from: Date()) {
                let formatter = DateFormatter()
                formatter.dateFormat = "d MMM, EEE" // e.g. 2 Mar, Mon
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
    }
}
