import AppKit
import Foundation

@main enum ShortcutChecks {
    @MainActor static func main() throws {
        let controller = ShortcutController()
        let flags = NSEvent.ModifierFlags([.control, .option, .command]).rawValue
        let first = Shortcut(keyCode: 18, modifiers: flags, key: "1")
        let second = Shortcut(keyCode: 19, modifiers: flags, key: "2")
        try controller.assign(first, to: .blackout, persist: false)
        do { try controller.assign(first, to: .lock, persist: false); fatalError("duplicate shortcut accepted") }
        catch { precondition(controller.bindings[.blackout] == first && controller.bindings[.lock] == nil) }
        do { try controller.assign(Shortcut(keyCode: 12, modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue, key: "Q"), to: .blackout, persist: false); fatalError("system shortcut accepted") }
        catch { precondition(controller.bindings[.blackout] == first) }
        for key in ["D", "H", "M"] {
            do { try Shortcut(keyCode: 2, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, key: key).validate(); fatalError("reserved system shortcut accepted") }
            catch {}
        }
        let functionKey = Shortcut(keyCode: 111, modifiers: flags, key: "F12")
        try controller.assign(functionKey, to: .open, persist: false)
        precondition(controller.bindings[.open]?.label == "⌃⌥⌘F12")
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: flags).union(.function), timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f70f}", charactersIgnoringModifiers: "\u{f70f}", isARepeat: false, keyCode: 111) {
            let captured = try Shortcut.capture(event)
            precondition(captured == functionKey)
        } else { fatalError("cannot create function-key event") }
        let occupier = ShortcutController()
        try occupier.assign(second, to: .lock, persist: false)
        do { try controller.assign(second, to: .blackout, persist: false); fatalError("occupied shortcut accepted") }
        catch { precondition(controller.bindings[.blackout] == first) }
        try controller.assign(nil, to: .blackout, persist: false)
        try occupier.assign(nil, to: .lock, persist: false)
        try controller.assign(nil, to: .open, persist: false)
        print("Shortcut checks passed: registration, F keys, duplicate, system conflict, occupied binding rollback.")
    }
}
