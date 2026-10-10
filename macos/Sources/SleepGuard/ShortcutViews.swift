import AppKit
import SwiftUI

struct ShortcutsSection: View {
    @ObservedObject var controller: ShortcutController
    @ViewState private var editing: ShortcutAction?
    @ViewState private var errors: [ShortcutAction: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionBox {
                ForEach(ShortcutAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Label(action.title, systemImage: action.icon)
                            Spacer()
                            Button(editing == action ? "请按组合键…" : controller.bindings[action]?.label ?? "未设置") { begin(action) }
                                .monospaced().frame(minWidth: 108).padding(.vertical, 6)
                                .buttonStyle(HoverButtonStyle(selected: editing == action))
                                .foregroundStyle(editing == action ? Color.accentColor : .secondary)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(editing == action ? Color.accentColor : Color.primary.opacity(0.12)))
                                .accessibilityLabel("设置\(action.title)快捷键")
                                .accessibilityValue(editing == action ? "录入中" : controller.bindings[action]?.label ?? "未设置")
                            if controller.bindings[action] != nil {
                                Button { do { try controller.assign(nil, to: action); errors[action] = nil; end() } catch { errors[action] = error.localizedDescription } } label: { Image(systemName: "xmark.circle").frame(width: 24, height: 24) }
                                    .buttonStyle(HoverButtonStyle()).foregroundStyle(.secondary).accessibilityLabel("清除\(action.title)快捷键")
                            }
                        }
                        if let error = errors[action] { Text(error).font(.caption).foregroundStyle(.orange) }
                        if editing == action {
                            KeyRecorder { event in
                                if [48, 53].contains(event.keyCode) { end(); return }
                                do { accept(try Shortcut.capture(event), for: action) }
                                catch { errors[action] = error.localizedDescription }
                            }.frame(width: 0, height: 0).accessibilityHidden(true)
                        }
                    }
                    .padding(14)
                    if action != .open { Divider() }
                }
                if let failure = controller.failure { Text(failure).font(.caption).foregroundStyle(.orange).padding(14) }
            }
            Text(editing == nil ? "点击录入组合键，Esc 取消。常用系统快捷键和重复组合不可用。" : "按下两个以上修饰键，加字母、数字或 F1–F19；Esc 取消。")
                .font(.caption).foregroundStyle(.secondary)
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: editing)
            .onDisappear { end() }
    }
    private func begin(_ action: ShortcutAction) {
        if editing == action { end(); return }
        editing = action; errors[action] = nil
        controller.recordingCapture = { shortcut in accept(shortcut, for: action) }
    }
    private func accept(_ shortcut: Shortcut, for action: ShortcutAction) {
        do { try controller.assign(shortcut, to: action); errors[action] = nil; end() }
        catch { errors[action] = error.localizedDescription }
    }
    private func end() {
        if let editing { errors[editing] = nil }
        editing = nil; controller.recordingCapture = nil
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
