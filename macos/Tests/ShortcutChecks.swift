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
        let occupier = ShortcutController()
        try occupier.assign(second, to: .lock, persist: false)
        do { try controller.assign(second, to: .blackout, persist: false); fatalError("occupied shortcut accepted") }
        catch { precondition(controller.bindings[.blackout] == first) }
        try controller.assign(nil, to: .blackout, persist: false)
        try occupier.assign(nil, to: .lock, persist: false)
        print("Shortcut checks passed: registration, duplicate, system conflict, occupied binding rollback.")
    }
}
