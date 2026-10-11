import SwiftUI

private struct MenuContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Measure the content, not ViewThatFits/ScrollView's proposed viewport. The
// explicit ideal size also makes MenuBarExtra shrink again after long content.
struct MenuPanelContainer<Content: View>: View {
    let maximumHeight: CGFloat
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
        .onPreferenceChange(MenuContentHeight.self) { contentHeight = $0 }
    }
}
