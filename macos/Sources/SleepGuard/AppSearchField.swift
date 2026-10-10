import AppKit
import SwiftUI

// NSTextField's editor consumes arrow and Return keys before SwiftUI move
// commands. Handle them in the native delegate so search stays focused while
// the user navigates the application results.
struct AppSearchField: NSViewRepresentable {
    @Binding var text: String
    let focus: Bool
    let navigate: (Int) -> Void
    let select: () -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> SearchField {
        let view = SearchField()
        view.placeholderString = "搜索应用、Bundle ID 或路径"
        view.setAccessibilityLabel("搜索应用")
        view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: SearchField, context: Context) {
        context.coordinator.parent = self
        if view.stringValue != text { view.stringValue = text }
        if view.shouldFocus != focus {
            view.shouldFocus = focus
            if focus { view.window?.makeFirstResponder(view) }
        }
    }
    final class SearchField: NSSearchField {
        var shouldFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if shouldFocus { window?.makeFirstResponder(self) }
        }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: AppSearchField
        init(parent: AppSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let view = notification.object as? NSSearchField { parent.text = view.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): parent.navigate(1)
            case #selector(NSResponder.moveUp(_:)): parent.navigate(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.select()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }
}
