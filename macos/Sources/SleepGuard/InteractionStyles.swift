import SwiftUI

// Keep motion short and honor the system's Reduce Motion preference.
struct HoverHighlight: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var hovering = false
    var selected = false
    var pressed = false
    func body(content: Content) -> some View {
        content
            .background(Color.accentColor.opacity(isEnabled && (hovering || pressed) ? 0.14 : selected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }
}
struct HoverButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(HoverHighlight(selected: selected, pressed: configuration.isPressed))
    }
}

// The whole header is a button, including the space to the right of the title.
struct ExpandableSection<Content: View>: View {
    let title: String
    @ViewState private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var content: Content
    init(_ title: String, initiallyExpanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        _expanded = State(initialValue: initiallyExpanded)
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 10)
            }.buttonStyle(HoverButtonStyle())
                .accessibilityLabel(title).accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                content.frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RefreshButton: View {
    let isRefreshing: Bool
    var label: String? = nil
    var help = "刷新状态"
    var unavailable = false
    let action: () async -> Void
    var body: some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 5) {
                ZStack {
                    if isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.8) }
                    else { Image(systemName: "arrow.clockwise") }
                }.frame(width: 16, height: 16)
                if let label { Text(isRefreshing ? "刷新中" : label).font(.system(size: 12)) }
            }.padding(.horizontal, label == nil ? 8 : 6).padding(.vertical, 6)
        }.buttonStyle(HoverButtonStyle()).disabled(isRefreshing || unavailable)
            .accessibilityLabel(isRefreshing ? "正在刷新" : help).help(help)
    }
}
