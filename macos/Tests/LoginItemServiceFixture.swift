import Foundation
import ServiceManagement

// Only test code owns this in-memory registry. No SMAppService is instantiated.
@MainActor final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registrationError: NSError?
    var unregistrationError: NSError?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        status = registrationStatus
    }

    func unregister(completionHandler: @escaping @Sendable (Error?) -> Void) {
        unregisterCalls += 1
        let error = unregistrationError
        if error == nil { status = .notRegistered }
        DispatchQueue.global(qos: .default).async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            completionHandler(error)
        }
    }
}
