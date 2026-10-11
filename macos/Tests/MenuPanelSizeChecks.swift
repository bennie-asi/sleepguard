import AppKit
import SwiftUI

@MainActor private final class ContentState: ObservableObject {
    @Published var height: CGFloat = 180
    @Published var limit: CGFloat = 400
}
private struct SizeFixture: View {
    @ObservedObject var state: ContentState
    var body: some View {
        MenuPanelContainer(maximumHeight: state.limit) {
            Color.blue.frame(width: 320, height: state.height)
        }
    }
}

@main enum MenuPanelSizeChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let state = ContentState()
        let hosting = NSHostingView(rootView: SizeFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        func check(_ expected: CGFloat) {
            let deadline = Date().addingTimeInterval(2)
            repeat {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                if abs(hosting.fittingSize.height - expected) < 1 { break }
            } while Date() < deadline
            let size = hosting.fittingSize
            precondition(abs(size.height - expected) < 1 && abs(size.width - 320) < 1,
                         "Expected 320 x \(expected), got \(size)")
            print("Menu panel measured: \(Int(size.width)) x \(Int(size.height))")
        }
        check(180)
        state.height = 900; check(400)
        state.height = 220; check(220)
        state.limit = 150; check(150)
        state.limit = 640; check(220)
        window.contentView = nil
        print("Menu panel checks passed: short, overflowing, short again, smaller screen and restored screen.")
    }
}
