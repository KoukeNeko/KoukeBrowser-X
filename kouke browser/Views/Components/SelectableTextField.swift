//
//  SelectableTextField.swift
//  kouke browser
//
//  A TextField wrapper that auto-selects all text when focused.
//

import SwiftUI
import AppKit

/// Custom NSTextField that selects all text when clicked
class AutoSelectTextField: NSTextField {
    var onBecomeFirstResponder: (() -> Void)?
    var onResignFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Select all text when becoming first responder
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let editor = self.currentEditor() {
                    editor.selectAll(nil)
                }
            }
            onBecomeFirstResponder?()
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // If this is the first click that focuses the field, select all
        if self.currentEditor() != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let editor = self.currentEditor() else { return }
                // Only select all if there's no selection yet (first click)
                if editor.selectedRange.length == 0 {
                    editor.selectAll(nil)
                }
            }
        }
    }
}

/// A TextField that automatically selects all text when it gains focus
struct SelectableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: (() -> Void)?
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?

    func makeNSView(context: Context) -> AutoSelectTextField {
        let textField = AutoSelectTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = NSColor(named: "TextMuted")
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.cell?.usesSingleLineMode = true

        let coordinator = context.coordinator
        textField.onBecomeFirstResponder = {
            coordinator.parent.onFocus?()
        }

        return textField
    }

    func updateNSView(_ nsView: AutoSelectTextField, context: Context) {
        // Only update if not currently editing to avoid cursor jumping
        if nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
        // Update callbacks
        let coordinator = context.coordinator
        nsView.onBecomeFirstResponder = {
            coordinator.parent.onFocus?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectableTextField

        init(_ parent: SelectableTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onBlur?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}
