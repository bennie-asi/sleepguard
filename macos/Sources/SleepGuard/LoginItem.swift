import AppKit
import ServiceManagement
import SwiftUI

@MainActor protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister(completionHandler: @escaping @Sendable (Error?) -> Void)
}

@MainActor struct SystemLoginItemService: LoginItemService {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister(completionHandler: @escaping @Sendable (Error?) -> Void) {
        service.unregister(completionHandler: completionHandler)
    }
}

@MainActor final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var changing = false
    @Published private(set) var failure: String?
    private let service: any LoginItemService

    init(service: any LoginItemService = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    // A pending request stays selected, but is clearly distinguished from enabled.
    var selected: Bool { status == .enabled || status == .requiresApproval }
    var enabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        guard !changing else { return }
        status = service.status
    }

    func setEnabled(_ enabled: Bool) async {
        guard !changing else { return }
        changing = true
        failure = nil
        defer { status = service.status; changing = false }
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
                guard service.status == .enabled || service.status == .requiresApproval else {
                    throw BackendFailure(message: "登录启动未能启用，请重试或检查系统登录项。")
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    service.unregister(completionHandler: Self.unregisterCompletion(continuation))
                }
                guard service.status == .notRegistered || service.status == .notFound else {
                    throw BackendFailure(message: "登录启动未能关闭，请重试或检查系统登录项。")
                }
            }
        } catch { failure = error.localizedDescription }
    }

    // ServiceManagement may call back off MainActor; resume on the caller's actor.
    nonisolated private static func unregisterCompletion(_ continuation: CheckedContinuation<Void, any Error>) -> @Sendable (Error?) -> Void {
        { error in
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume() }
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

enum LoginLaunch {
    static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
