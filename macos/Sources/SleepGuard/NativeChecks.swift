import AppKit
import Foundation
import Security

// Headless diagnostics use only a disposable item, never a saved user token.
enum NativeChecks {
    static func keychain() -> Int32 {
        let service = "sleepguard.check." + UUID().uuidString
        let value = UUID().uuidString
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: NSUserName()]
        defer { SecItemDelete(query as CFDictionary) }
        do {
            try Keychain.save(value, service: service)
            for _ in 0..<3 {
                let child = Process()
                child.executableURL = Bundle.main.executableURL
                child.arguments = ["--check-keychain-item", service]
                child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
                try child.run(); child.waitUntilExit()
                guard child.terminationStatus == 0 else { print("Keychain non-interactive reopen check failed"); return 1 }
            }
            print("Keychain: three independent reads succeeded without interaction")
            return 0
        } catch { print("Keychain diagnostic unavailable"); return 1 }
    }
    static func item() -> Int32 {
        guard CommandLine.arguments.count == 3, CommandLine.arguments[2].hasPrefix("sleepguard.check.") else { return 2 }
        return (try? Keychain.read(service: CommandLine.arguments[2])) == nil ? 3 : 0
    }
}
