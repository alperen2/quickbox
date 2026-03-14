import SwiftUI
import AppKit

struct CustomTextFieldWithKeyHandling: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var accessibilityIdentifier: String?

    // Return true if the event was handled by the callback (so the default behavior is swallowed)
    var onUpArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> CustomNSTextField {
        let textField = CustomNSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = prompt
        textField.stringValue = text
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 30, weight: .regular)
        textField.textColor = NSColor.white.withAlphaComponent(0.95)
        textField.allowsEditingTextAttributes = true
        textField.importsGraphics = false
        textField.setAccessibilityIdentifier(accessibilityIdentifier)

        textField.onUpArrow = onUpArrow
        textField.onDownArrow = onDownArrow
        textField.onEnter = onEnter
        textField.onTab = onTab
        textField.onEscape = onEscape

        textField.applySyntaxHighlighting()
        return textField
    }

    func updateNSView(_ nsView: CustomNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.onUpArrow = onUpArrow
        nsView.onDownArrow = onDownArrow
        nsView.onEnter = onEnter
        nsView.onTab = onTab
        nsView.onEscape = onEscape
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.applySyntaxHighlighting()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextFieldWithKeyHandling

        init(_ parent: CustomTextFieldWithKeyHandling) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? CustomNSTextField else { return }
            parent.text = textField.stringValue
            textField.applySyntaxHighlighting()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let onEnter = parent.onEnter, onEnter() {
                    return true // Swallowed by autocomplete
                }
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}

class CustomNSTextField: NSTextField {
    private struct MetadataHighlightRange {
        let key: String
        let keyRange: NSRange
        let valueRange: NSRange
        let fullRange: NSRange
    }

    private enum SyntaxHighlightStyle {
        case subtle
        case vivid
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: #"\S+"#)
    private static let metadataKeyPattern = try! NSRegularExpression(pattern: #"^[a-zA-Z0-9_\-]+$"#)
    private static let nextMetadataPattern = try! NSRegularExpression(pattern: #"^[a-zA-Z0-9_\-]+:"#)
    private static let compactRelativeDatePattern = try! NSRegularExpression(pattern: #"^in\d+(day|days|d|week|weeks|w|month|months|m)$"#)
    private static let numericPattern = try! NSRegularExpression(pattern: #"^\d+$"#)

    private static let dateMetadataKeys: Set<String> = ["due", "defer", "start"]
    private static let syntaxHighlightStyle: SyntaxHighlightStyle = .subtle
    private static let datePhraseTokens: Set<String> = [
        "today", "tdy",
        "tomorrow", "tmr",
        "next",
        "in",
        "week", "weekend",
        "weeks",
        "end", "of",
        "day", "days",
        "month", "months",
        "year",
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"
    ]

    var onUpArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onEscape: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 125 { // Down Arrow
                if onDownArrow?() == true { return true }
            } else if event.keyCode == 126 { // Up Arrow
                if onUpArrow?() == true { return true }
            } else if event.keyCode == 36 { // Enter
                if onEnter?() == true { return true }
            } else if event.keyCode == 48 { // Tab
                if onTab?() == true { return true }
            } else if event.keyCode == 53 { // Escape
                if onEscape?() == true { return true }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    func applySyntaxHighlighting() {
        let text = stringValue
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)

        for metadata in metadataHighlightRanges(in: text) {
            attributed.addAttribute(.foregroundColor, value: fullTokenColor(forMetadataKey: metadata.key), range: metadata.fullRange)
            attributed.addAttribute(.foregroundColor, value: valueColor(forMetadataKey: metadata.key), range: metadata.valueRange)
            attributed.addAttribute(.foregroundColor, value: keyColor(forMetadataKey: metadata.key), range: metadata.keyRange)
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 30, weight: keyFontWeight), range: metadata.keyRange)
        }

        if let textView = currentEditor() as? NSTextView, let storage = textView.textStorage {
            let selectedRange = textView.selectedRange()
            storage.setAttributedString(attributed)
            textView.setSelectedRange(selectedRange)
            textView.insertionPointColor = NSColor.white.withAlphaComponent(0.95)
        } else {
            attributedStringValue = attributed
        }
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
    }

    private func metadataHighlightRanges(in text: String) -> [MetadataHighlightRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let tokenMatches = Self.tokenRegex.matches(in: text, options: [], range: fullRange)
        if tokenMatches.isEmpty {
            return []
        }

        var ranges: [MetadataHighlightRange] = []
        var index = 0

        while index < tokenMatches.count {
            let tokenRange = tokenMatches[index].range
            let token = nsText.substring(with: tokenRange)

            guard let colonRange = token.range(of: ":") else {
                index += 1
                continue
            }

            let key = String(token[..<colonRange.lowerBound]).lowercased()
            guard isValidMetadataKey(key), key != "http", key != "https" else {
                index += 1
                continue
            }

            let keyLength = key.count + 1 // include ':'
            let keyRange = NSRange(location: tokenRange.location, length: min(keyLength, tokenRange.length))

            var highlightEnd = tokenRange.location + tokenRange.length
            let inlineValueStart = keyRange.location + keyRange.length
            var valueRange = NSRange(location: inlineValueStart, length: max(0, highlightEnd - inlineValueStart))

            if Self.dateMetadataKeys.contains(key) {
                var lookahead = index + 1
                while lookahead < tokenMatches.count {
                    let nextRange = tokenMatches[lookahead].range
                    let nextToken = nsText.substring(with: nextRange)
                    if shouldContinueDatePhrase(with: nextToken) {
                        highlightEnd = nextRange.location + nextRange.length
                        lookahead += 1
                    } else {
                        break
                    }
                }

                valueRange = NSRange(location: inlineValueStart, length: max(0, highlightEnd - inlineValueStart))
                index = lookahead
            } else {
                index += 1
            }

            let fullMetadataRange = NSRange(location: tokenRange.location, length: max(0, highlightEnd - tokenRange.location))
            ranges.append(
                MetadataHighlightRange(
                    key: key,
                    keyRange: keyRange,
                    valueRange: valueRange,
                    fullRange: fullMetadataRange
                )
            )
        }

        return ranges
    }

    private func isValidMetadataKey(_ key: String) -> Bool {
        let range = NSRange(location: 0, length: key.utf16.count)
        return Self.metadataKeyPattern.firstMatch(in: key, options: [], range: range) != nil
    }

    private func shouldContinueDatePhrase(with token: String) -> Bool {
        let normalized = token.lowercased()
        if normalized.hasPrefix("#") || normalized.hasPrefix("@") || normalized.hasPrefix("!") {
            return false
        }
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return false
        }

        let range = NSRange(location: 0, length: normalized.utf16.count)
        if Self.nextMetadataPattern.firstMatch(in: normalized, options: [], range: range) != nil {
            return false
        }
        if Self.datePhraseTokens.contains(normalized) {
            return true
        }
        if Self.numericPattern.firstMatch(in: normalized, options: [], range: range) != nil {
            return true
        }
        if Self.compactRelativeDatePattern.firstMatch(in: normalized, options: [], range: range) != nil {
            return true
        }
        return false
    }

    private var keyFontWeight: NSFont.Weight {
        switch Self.syntaxHighlightStyle {
        case .subtle:
            return .medium
        case .vivid:
            return .semibold
        }
    }

    private func keyColor(forMetadataKey key: String) -> NSColor {
        switch Self.syntaxHighlightStyle {
        case .subtle:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.72)
        case .vivid:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.98)
        }
    }

    private func valueColor(forMetadataKey key: String) -> NSColor {
        switch Self.syntaxHighlightStyle {
        case .subtle:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.48)
        case .vivid:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.82)
        }
    }

    private func fullTokenColor(forMetadataKey key: String) -> NSColor {
        switch Self.syntaxHighlightStyle {
        case .subtle:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.58)
        case .vivid:
            return baseColor(forMetadataKey: key).withAlphaComponent(0.90)
        }
    }

    private func baseColor(forMetadataKey key: String) -> NSColor {
        switch key {
        case "due", "defer", "start":
            return NSColor.systemBlue
        case "dur", "time", "duration":
            return NSColor.systemTeal
        case "remind", "alarm":
            return NSColor.systemOrange
        default:
            return NSColor.systemPurple
        }
    }
}
