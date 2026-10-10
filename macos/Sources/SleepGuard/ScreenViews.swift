import AppKit
import SwiftUI

private struct ConnectedDisplay: Identifiable {
    let id: UInt32
    let name: String
    let builtIn: Bool
    @MainActor static func current() -> [ConnectedDisplay] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return ConnectedDisplay(id: id, name: screen.localizedName, builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }
}
struct ScreenOperationsSection: View {
    @ObservedObject var model: GuardModel
    @ViewState private var displays = ConnectedDisplay.current()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionBox {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("黑屏").font(.headline)
                            Text("所有显示器").font(.caption).foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.accentColor.opacity(0.08), in: Capsule())
                        }
                        Text("不锁屏；任意按键或点击恢复全部屏幕。").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("立即黑屏") { Task { await model.blackout() } }.disabled(model.busy)
                }.padding(14)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(displays) { display in
                        VStack(spacing: 7) {
                            Image(systemName: display.builtIn ? "laptopcomputer" : "display")
                                .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                            Text(display.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                            .help(display.name).accessibilityLabel("\(display.name)，将一起黑屏")
                    }
                }.padding(.horizontal, 14).padding(.bottom, 14)
                Divider()
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("锁屏", systemImage: "lock").font(.headline)
                        Text("立即锁定桌面。").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("立即锁屏") { model.lockScreen() }.disabled(model.busy)
                }.padding(14)
            }
            Text("黑屏为纯黑遮罩，屏幕本身不断电。").font(.caption).foregroundStyle(.secondary)
        }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in displays = ConnectedDisplay.current() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: displays.map(\.id))
    }
}

struct ScreenQuickButton: View {
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(HoverButtonStyle())
    }
}
