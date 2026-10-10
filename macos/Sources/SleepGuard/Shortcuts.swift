import AppKit
import Carbon
import SwiftUI

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case blackout, lock, open
    var id: String { rawValue }
    var title: String { switch self { case .blackout: "所有屏幕黑屏"; case .lock: "锁定屏幕"; case .open: "打开 SleepGuard" } }
    var icon: String { switch self { case .blackout: "display"; case .lock: "lock"; case .open: "moon.stars" } }
    var number: UInt32 { switch self { case .blackout: 1; case .lock: 2; case .open: 3 } }
}
struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt
    let key: String
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var label: String { (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key }
    var carbonModifiers: UInt32 {
        (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0) | (flags.contains(.command) ? UInt32(cmdKey) : 0)
    }
    // macOS function keys have non-contiguous virtual key codes.
    private static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"
    ]
    static func capture(_ event: NSEvent) throws -> Shortcut {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = functionKeys[UInt32(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard flags.rawValue.nonzeroBitCount >= 2,
              key.range(of: "^(?:[A-Z0-9]|F(?:[1-9]|1[0-9]))$", options: .regularExpression) != nil else { throw BackendFailure(message: "请使用至少两个修饰键，加一个字母、数字或功能键。") }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, key: key)
        try shortcut.validate()
        return shortcut
    }
    func validate() throws {
        let allowedFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        guard flags == flags.intersection(allowedFlags), flags.rawValue.nonzeroBitCount >= 2, keyCode <= 127,
              key.range(of: "^(?:[A-Z0-9]|F(?:[1-9]|1[0-9]))$", options: .regularExpression) != nil,
              !key.hasPrefix("F") || key.count == 1 || Self.functionKeys[keyCode] == key else { throw BackendFailure(message: "快捷键格式无效。") }
        if (flags == [.control, .command] && key == "Q") ||
            (flags.contains([.command, .shift]) && key == "Q") ||
            (flags.contains([.command, .shift]) && ["3", "4", "5", "6"].contains(key)) ||
            (flags == [.command, .option] && ["D", "H", "M"].contains(key)) ||
            (flags == [.control, .shift] && ["F2", "F3", "F4", "F5", "F6", "F7", "F8"].contains(key)) {
            throw BackendFailure(message: "此组合是常用系统快捷键，请换一个。")
        }
    }
}
private func sleepGuardHotkey(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard result == noErr else { return result }
    let address = UInt(bitPattern: context)
    let number = identifier.id
    MainActor.assumeIsolated {
        let controller = Unmanaged<ShortcutController>.fromOpaque(UnsafeMutableRawPointer(bitPattern: address)!).takeUnretainedValue()
        if let action = ShortcutAction.allCases.first(where: { $0.number == number }) {
            // Recording an existing binding must never black out or lock the desktop.
            if let capture = controller.recordingCapture, let shortcut = controller.bindings[action] { capture(shortcut) }
            else { controller.onAction?(action) }
        }
    }
    return noErr
}
@MainActor final class ShortcutController: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: Shortcut] = [:]
    @Published var failure: String?
    var onAction: ((ShortcutAction) -> Void)?
    var recordingCapture: ((Shortcut) -> Void)?
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var attempted = false
    private func installHandler() throws {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let code = InstallEventHandler(GetApplicationEventTarget(), sleepGuardHotkey, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard code == noErr else { throw BackendFailure(message: "无法注册全局快捷键。") }
    }
    func load() {
        guard !attempted else { return }; attempted = true
        guard let data = UserDefaults.standard.data(forKey: "globalShortcuts"), let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) else { return }
        for action in ShortcutAction.allCases {
            if let value = saved[action.rawValue] { do { try assign(value, to: action, persist: false) } catch { failure = "\(action.title)：\(error.localizedDescription)" } }
        }
    }
    func assign(_ shortcut: Shortcut?, to action: ShortcutAction, persist: Bool = true) throws {
        if let shortcut {
            try shortcut.validate()
            guard !bindings.contains(where: { $0.key != action && $0.value.keyCode == shortcut.keyCode && $0.value.modifiers == shortcut.modifiers }) else { throw BackendFailure(message: "此组合已用于其他功能。") }
            if bindings[action] == shortcut { return }
            try installHandler()
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, EventHotKeyID(signature: 0x534C5047, id: action.number), GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else { throw BackendFailure(message: "此组合未能注册，可能被系统或其他应用占用；原快捷键已保留。") }
            if let previous = references[action] { UnregisterEventHotKey(previous) }
            references[action] = reference; bindings[action] = shortcut
        } else {
            if let previous = references.removeValue(forKey: action) { UnregisterEventHotKey(previous) }
            bindings[action] = nil
        }
        failure = nil
        if persist { UserDefaults.standard.set(try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })), forKey: "globalShortcuts") }
    }
}
