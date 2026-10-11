import AppKit
import SwiftUI

@MainActor private final class ContentState: ObservableObject {
    @Published var height: CGFloat = 180
}
private struct SizeFixture: View {
    @ObservedObject var state: ContentState
    @ObservedObject var presentation: MenuPresentation
    var body: some View {
        MenuPanelContainer(maximumHeight: presentation.maximumHeight, onHeightChange: presentation.updateContentHeight) {
            Color.blue.frame(width: 320, height: state.height)
        }
        .background(MenuWindowReader(presentation: presentation).frame(width: 0, height: 0))
    }
}

@main enum MenuPanelSizeChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let state = ContentState()
        let presentation = MenuPresentation()
        let hosting = NSHostingView(rootView: SizeFixture(state: state, presentation: presentation))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        let top = window.frame.maxY
        func check(_ expected: CGFloat) {
            let deadline = Date().addingTimeInterval(2)
            repeat {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                if abs(hosting.fittingSize.height - expected) < 1 && abs(window.frame.height - expected) < 1 { break }
            } while Date() < deadline
            let size = hosting.fittingSize
            precondition(abs(size.height - expected) < 1 && abs(size.width - 320) < 1,
                         "Expected 320 x \(expected), got \(size)")
            precondition(abs(window.frame.height - expected) < 1 && abs(window.frame.maxY - top) < 1,
                         "Host window did not follow content or keep its top anchor: \(window.frame)")
            precondition(abs(hosting.frame.height - expected) < 1, "Content view retained unused host space: \(hosting.frame)")
            print("Menu content and window measured: \(Int(size.width)) x \(Int(size.height))")
        }
        check(180)
        state.height = 900; check(640)
        state.height = 220; check(220)
        presentation.updateHeightLimit(availableHeight: 166); check(150)
        presentation.updateHeightLimit(availableHeight: 800); check(220)
        // Simulate a host restoring its cached first-presentation size.
        window.setContentSize(NSSize(width: 320, height: 640))
        let restoredTop = window.frame.maxY
        presentation.fitWindowToContent()
        precondition(window.frame.height == 220 && window.frame.maxY == restoredTop)
        window.contentView = nil
        print("Menu panel checks passed: short, overflowing, short again, smaller screen and restored screen.")
    }
}
