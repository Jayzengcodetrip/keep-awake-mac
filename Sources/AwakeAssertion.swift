import Foundation
import IOKit.pwr_mgt

/// Owns only this application's idle-sleep assertion, equivalent to `caffeinate -i`.
/// Call from AppKit's main actor. Normal termination should call `disable()` explicitly.
@MainActor
final class AwakeAssertion {
    struct Failure: LocalizedError {
        let operation: String
        let code: IOReturn

        var errorDescription: String? {
            "\(operation)失败（系统错误 \(String(format: "0x%08x", UInt32(bitPattern: code)))）。"
        }
    }

    struct Snapshot {
        let id: IOPMAssertionID
        let name: String
        let type: String
        let level: UInt32

        var isActive: Bool { level == UInt32(kIOPMAssertionLevelOn) }
    }

    private(set) var assertionID: IOPMAssertionID?
    private let reason: String

    /// Whether a successful creation is still owned by this instance.
    /// This does not inspect or control assertions held by other applications.
    var isEnabled: Bool { assertionID != nil }

    init(reason: String = "保持运行 — 允许锁屏时继续后台任务") {
        self.reason = String(reason.prefix(128))
    }

    func enable() throws {
        guard assertionID == nil else { return }
        var createdID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &createdID
        )
        guard result == kIOReturnSuccess else {
            throw Failure(operation: "开启保持运行", code: result)
        }
        assertionID = createdID
    }

    func disable() throws {
        guard let id = assertionID else { return }
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else {
            // Keep the ownership/state intact if release has not succeeded.
            throw Failure(operation: "关闭保持运行", code: result)
        }
        assertionID = nil
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    func toggle() throws {
        try setEnabled(!isEnabled)
    }

    /// Queries the system for this owned assertion; nil means this instance owns none.
    /// Query failure is an error, not proof that the computer can sleep.
    func snapshot() throws -> Snapshot? {
        guard let id = assertionID else { return nil }
        guard let copied = IOPMAssertionCopyProperties(id) else {
            throw Failure(operation: "读取保持运行状态", code: kIOReturnNotFound)
        }
        let properties = copied.takeRetainedValue() as NSDictionary
        guard let level = properties[kIOPMAssertionLevelKey] as? NSNumber,
              let type = properties[kIOPMAssertionTypeKey] as? String else {
            throw Failure(operation: "解析保持运行状态", code: kIOReturnError)
        }
        return Snapshot(
            id: id,
            name: properties[kIOPMAssertionNameKey] as? String ?? reason,
            type: type,
            level: level.uint32Value
        )
    }

    deinit {
        // Process termination also removes its assertions; this covers earlier destruction.
        if let id = assertionID {
            IOPMAssertionRelease(id)
        }
    }
}
