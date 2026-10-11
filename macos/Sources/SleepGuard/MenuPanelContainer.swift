import SwiftUI

private struct MenuContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Measure natural content separately from the viewport, and report it to the
// AppKit window owner: MenuBarExtra may retain its initial host window size.
struct MenuPanelContainer<Content: View>: View {
    let maximumHeight: CGFloat
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder var content: () -> Content
    @ViewState private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: MenuContentHeight.self, value: geometry.size.height)
                })
        }
        .frame(width: 320, height: min(contentHeight > 0 ? ceil(contentHeight) : maximumHeight, maximumHeight), alignment: .top)
        .fixedSize()
        .onPreferenceChange(MenuContentHeight.self) {
            contentHeight = $0
            onHeightChange($0)
        }
    }
}
