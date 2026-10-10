import Foundation
import Sparkle
import Darwin

@MainActor final class GuardModel {
    func prepareForUpdate(continuingUpdate: Bool = false) async throws {}
    func restoreAfterFailedUpdate() async {}
}

@main struct UpdateCoreChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sleepguard-update-core-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        setenv("SLEEPGUARD_STATE_DIR", directory.path, 1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = Data(#"{"previousBuild":"4001","watcherWasRunning":true,"createdAt":0}"#.utf8)
        try old.write(to: UpdateRecovery.location)
        let legacy = try UpdateRecovery.take()
        precondition(legacy?.continuingUpdate == nil && legacy?.watcherWasRunning == true)
        try UpdateRecovery(previousBuild: "4001", watcherWasRunning: false, createdAt: Date(), continuingUpdate: true).save()
        let permissions = try FileManager.default.attributesOfItem(atPath: UpdateRecovery.location.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        let resumed = try UpdateRecovery.take()
        precondition(resumed?.continuingUpdate == true && resumed?.watcherWasRunning == false)
        let consumed = try UpdateRecovery.take()
        precondition(consumed == nil)
        precondition(UpdateRelaunch.executableIsCurrent)
        let rejected = await UpdateRelaunch.runHelper(arguments: [String(getppid()), "/tmp/ready"])
        precondition(rejected == 2)
        let installation = NSError(domain: SUSparkleErrorDomain, code: 4005,
                                   userInfo: [NSLocalizedDescriptionKey: "Installer failed",
                                              NSLocalizedFailureReasonErrorKey: "Authorization failed",
                                              NSUnderlyingErrorKey: NSError(domain: "Authorization", code: -60008,
                                                                            userInfo: [NSLocalizedDescriptionKey: "Invalid process identity"])])
        precondition(UpdateFailure.title(for: installation) == "安装更新失败")
        precondition(UpdateFailure.details(for: installation).contains("Invalid process identity"))
        precondition(UpdateFailure.title(for: NSError(domain: SUSparkleErrorDomain, code: 2001)) == "下载更新失败")
        precondition(UpdateFailure.title(for: NSError(domain: SUSparkleErrorDomain, code: 3001)) == "验证更新失败")
        precondition(UpdateFailure.title(for: NSError(domain: SUSparkleErrorDomain, code: 4009)) == "验证更新失败")
        let wrappedSignature = NSError(domain: SUSparkleErrorDomain, code: 4005,
                                       userInfo: [NSUnderlyingErrorKey: NSError(domain: SUSparkleErrorDomain, code: 3001)])
        precondition(UpdateFailure.title(for: wrappedSignature) == "验证更新失败")
        print("Update checks passed: recovery compatibility, private state, helper scope and error phases")
    }
}
