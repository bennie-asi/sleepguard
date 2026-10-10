import Foundation

// Run inside the same signed executable that owns the Keychain item. Tokens never
// leave this process and background delivery never opens an authorization dialog.
enum TelegramHelper {
    struct Message: Decodable {
        let service: String
        let chatID: Int64
        let title: String
        let body: String
        let timeout: Double
    }
    private final class Result: @unchecked Sendable {
        private let lock = NSLock()
        private var success = false
        func set(_ value: Bool) { lock.withLock { success = value } }
        func get() -> Bool { lock.withLock { success } }
    }
    static func send() -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard data.count <= 1024 * 1024, let message = try? JSONDecoder().decode(Message.self, from: data), message.chatID != 0 else { return 2 }
        guard let token = try? Keychain.read(service: message.service),
              token.range(of: "^[0-9]+:[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return 3 }
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage") else { return 3 }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": message.chatID, "text": message.title + "\n\n" + message.body])
        request.timeoutInterval = max(1, min(message.timeout, 60))
        let semaphore = DispatchSemaphore(value: 0), result = Result()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request) { data, response, error in
            if error == nil, let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
               let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["ok"] as? Bool == true {
                result.set(true)
            }
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + request.timeoutInterval + 1) == .success else { return 4 }
        return result.get() ? 0 : 4
    }
}
