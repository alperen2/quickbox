import SwiftUI
import AppKit

struct CustomTextFieldWithKeyHandling: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    
    // Return true if the event was handled by the callback (so the default behavior is swallowed)
    var onUpArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onTab: (() -> Bool)?
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
        
        textField.onUpArrow = onUpArrow
        textField.onDownArrow = onDownArrow
        textField.onEnter = onEnter
        textField.onTab = onTab
        
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
            guard let textField = obj.object as? NSTextField else { return }
            parent.text = textField.stringValue
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
    var onUpArrow: (() -> Bool)?
    var onDownArrow: (() -> Bool)?
    var onEnter: (() -> Bool)?
    var onTab: (() -> Bool)?
    
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
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
