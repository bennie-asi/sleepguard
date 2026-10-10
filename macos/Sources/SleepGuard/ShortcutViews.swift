import AppKit
import SwiftUI

struct ShortcutsSection: View {
    @ObservedObject var controller: ShortcutController
    @ViewState private var editing: ShortcutAction?
    var body: some View {
        SectionBox {
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.title); Spacer()
                    Button(controller.bindings[action]?.label ?? "录入快捷键") { editing = action }.controlSize(.small)
                    if controller.bindings[action] != nil {
                        Button { try? controller.assign(nil, to: action) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(HoverButtonStyle()).accessibilityLabel("清除\(action.title)快捷键")
                    }
                }.padding(14)
                if action != .open { Divider() }
            }
            if let failure = controller.failure { Text(failure).font(.caption).foregroundStyle(.orange).padding(14) }
        }.sheet(item: $editing) { action in ShortcutEditor(controller: controller, action: action) }
    }
}
private struct ShortcutEditor: View {
    @ObservedObject var controller: ShortcutController
    let action: ShortcutAction
    @Environment(\.dismiss) private var dismiss
    @ViewState private var error: String?
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard").font(.largeTitle).foregroundStyle(.blue)
            Text(action.title).font(.title3.weight(.semibold))
            Text("按下至少两个修饰键，再加一个字母或数字。\n常用系统快捷键和重复组合无法使用。").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            KeyRecorder { event in
                if event.keyCode == 53 { dismiss(); return }
                do { try controller.assign(Shortcut.capture(event), to: action); dismiss() }
                catch { self.error = error.localizedDescription }
            }.frame(width: 1, height: 1)
        }.padding(28).frame(width: 370)
    }
}
private struct KeyRecorder: NSViewRepresentable {
    let capture: (NSEvent) -> Void
    func makeNSView(context: Context) -> Recorder { Recorder(capture: capture) }
    func updateNSView(_ view: Recorder, context: Context) { view.capture = capture }
    final class Recorder: NSView {
        var capture: (NSEvent) -> Void
        init(capture: @escaping (NSEvent) -> Void) { self.capture = capture; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) { capture(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { capture(event); return true }
    }
}
