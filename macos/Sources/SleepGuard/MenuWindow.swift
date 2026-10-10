import AppKit
import SwiftUI

@MainActor final class MenuPresentation {
    weak var window: NSWindow?
    func dismiss() { window?.close() }
}

// Capture only this menu panel's own window, never the management window.
struct MenuWindowReader: NSViewRepresentable {
    let presentation: MenuPresentation
    func makeNSView(context: Context) -> MenuWindowView { MenuWindowView(presentation: presentation) }
    func updateNSView(_ view: MenuWindowView, context: Context) {
        if let window = view.window { presentation.window = window }
    }
}
final class MenuWindowView: NSView {
    let presentation: MenuPresentation
    init(presentation: MenuPresentation) { self.presentation = presentation; super.init(frame: .zero) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { presentation.window = window }
    }
}
