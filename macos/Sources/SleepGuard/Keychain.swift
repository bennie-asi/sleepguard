import Foundation
import Security
import LocalAuthentication

enum Keychain {
    static func contains(service: String) -> Bool {
        guard !service.isEmpty else { return false }
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: NSUserName(), kSecReturnAttributes as String: true, kSecUseAuthenticationContext as String: context]
        let result = SecItemCopyMatching(query as CFDictionary, nil)
        return result == errSecSuccess || result == errSecInteractionNotAllowed
    }
    static func read(service: String, interactive: Bool = false) throws -> String {
        guard service.hasPrefix("sleepguard.") else { throw BackendFailure(message: "凭据服务名称必须以 sleepguard. 开头。请重新保存此渠道。") }
        let context = LAContext(); context.interactionNotAllowed = !interactive
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: NSUserName(), kSecReturnData: true, kSecUseAuthenticationContext: context]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        guard code == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw BackendFailure(message: "未能读取钥匙串凭据。请重新保存 Token，或在 macOS 授权窗口选择“始终允许”。")
        }
        return token
    }
    static func save(_ token: String, service: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: NSUserName()]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            result = SecItemAdd(item as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw BackendFailure(message: "钥匙串保存失败：\(SecCopyErrorMessageString(result, nil) as String? ?? "\(result)")") }
    }
}
