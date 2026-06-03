import AppKit
import SwiftUI

struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = placeholder
        field.controlSize = .small
        field.font = .systemFont(ofSize: 12)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        context.coordinator.storeField(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding private var text: String
        private var field: NSSearchField?

        init(text: Binding<String>) {
            _text = text
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusSearch),
                name: .focusSearchField,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            text = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text = field.stringValue
        }

        func storeField(_ field: NSSearchField) {
            self.field = field
        }

        @objc private func handleFocusSearch() {
            guard let field else { return }
            NSApp.keyWindow?.makeFirstResponder(field)
        }
    }
}
