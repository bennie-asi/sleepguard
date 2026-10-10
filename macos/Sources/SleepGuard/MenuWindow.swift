import AppKit
import SwiftUI

@MainActor final class MenuPresentation: ObservableObject {
    weak var window: NSWindow?
    @Published private(set) var maximumHeight: CGFloat = 640
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        Task { @MainActor [weak self] in self?.updateHeightLimit() }
    }
    func updateHeightLimit() {
        let available = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let limit = max(1, min(640, available - 16))
        if maximumHeight != limit { maximumHeight = limit }
    }
    func dismiss() { window?.close() }
}

// Capture only this menu panel's own window, never the management window.
struct MenuWindowReader: NSViewRepresentable {
    let presentation: MenuPresentation
    func makeNSView(context: Context) -> MenuWindowView { MenuWindowView(presentation: presentation) }
    func updateNSView(_ view: MenuWindowView, context: Context) {
        if let window = view.window { presentation.attach(window) }
    }
}
final class MenuWindowView: NSView {
    let presentation: MenuPresentation
    init(presentation: MenuPresentation) { self.presentation = presentation; super.init(frame: .zero) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { presentation.attach(window) }
    }
}
