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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 6) {
                        icon(for: mode)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(iconColor(for: mode))
                        
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(index == selectedIndex ? .white : .primary)
                        
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
}
