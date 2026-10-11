import AppKit
import ServiceManagement

@main enum LoginItemChecks {
    @MainActor static func main() async {
        precondition(!LoginLaunch.isLoginItem(nil))
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        precondition(!LoginLaunch.isLoginItem(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        precondition(LoginLaunch.isLoginItem(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsServiceItem)), forKeyword: AEKeyword(keyAEPropData))
        precondition(!LoginLaunch.isLoginItem(event))

        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service)
        precondition(!controller.enabled && !controller.selected)
        await controller.setEnabled(true)
        precondition(controller.enabled && controller.failure == nil && service.registerCalls == 1)
        await controller.setEnabled(true)
        precondition(service.registerCalls == 1, "repeated enable must not register again")
        await controller.setEnabled(false)
        MainActor.assertIsolated()
        precondition(!controller.selected && controller.failure == nil && service.unregisterCalls == 1)
        await controller.setEnabled(false)
        precondition(service.unregisterCalls == 1, "repeated disable must not unregister again")

        service.registrationStatus = .requiresApproval
        await controller.setEnabled(true)
        precondition(controller.selected && !controller.enabled && controller.requiresApproval)
        await controller.setEnabled(true)
        precondition(service.registerCalls == 2, "pending approval must not register again")
        service.status = .enabled
        controller.refresh()
        precondition(controller.enabled && !controller.requiresApproval, "external approval must refresh")

        service.unregistrationError = NSError(domain: "LoginFixture", code: 7,
                                             userInfo: [NSLocalizedDescriptionKey: "fixture unregister rejected"])
        await controller.setEnabled(false)
        precondition(controller.enabled && controller.failure == "fixture unregister rejected" && !controller.changing)
        service.unregistrationError = nil
        await controller.setEnabled(false)
        precondition(!controller.enabled && controller.failure == nil)

        service.registrationError = NSError(domain: "LoginFixture", code: 8,
                                           userInfo: [NSLocalizedDescriptionKey: "fixture register rejected"])
        await controller.setEnabled(true)
        precondition(!controller.enabled && controller.failure == "fixture register rejected" && !controller.changing)
        print("Login controller checks passed (events, idempotency, approval, background completion, error recovery); system registry untouched.")
    }
}
