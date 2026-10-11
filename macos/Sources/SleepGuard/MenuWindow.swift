import AppKit
import SwiftUI

@MainActor final class MenuPresentation: ObservableObject {
    weak var window: NSWindow?
    @Published private(set) var maximumHeight: CGFloat = 640
    private var contentHeight: CGFloat = 0
    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        Task { @MainActor [weak self] in self?.updateHeightLimit() }
    }
    func updateHeightLimit() {
        let available = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        updateHeightLimit(availableHeight: available)
    }
    func updateHeightLimit(availableHeight: CGFloat) {
        let limit = max(1, min(640, availableHeight - 16))
        if maximumHeight != limit { maximumHeight = limit }
        fitWindowToContent()
    }
    func updateContentHeight(_ height: CGFloat) {
        guard height > 0, height.isFinite else { return }
        contentHeight = height
        fitWindowToContent()
    }
    func fitWindowToContent() {
        guard let window, contentHeight > 0 else { return }
        let size = NSSize(width: 320, height: min(ceil(contentHeight), maximumHeight))
        guard window.contentRect(forFrameRect: window.frame).size != size else { return }
        // Keep the menu attached to the same point below the menu bar while
        // growing or shrinking; resizing about the centre leaves empty margins.
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
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
