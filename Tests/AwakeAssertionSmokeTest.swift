import Darwin
import Foundation
import IOKit.pwr_mgt

/// Standalone, opt-in diagnostic. Compile separately from the menu-bar app.
/// Its own assertion has a system-enforced 20-second release timeout.
@main
struct AwakeAssertionSmokeTest {
    @MainActor
    static func main() {
        let manager = AwakeAssertion(reason: "Keep Awake diagnostic — maximum 20 seconds")
        var exitCode: Int32 = 0
        do {
            guard !manager.isEnabled, try manager.snapshot() == nil else {
                throw DiagnosticFailure(message: "初始状态应为关闭。")
            }
            try manager.enable()
            guard let id = manager.assertionID else {
                throw DiagnosticFailure(message: "创建成功后未返回 assertion ID。")
            }
            defer { try? manager.disable() }

            try check(IOPMAssertionSetProperty(
                id,
                kIOPMAssertionTimeoutActionKey as CFString,
                kIOPMAssertionTimeoutActionRelease as CFString
            ), operation: "设置自动释放")
            try check(IOPMAssertionSetProperty(
                id,
                kIOPMAssertionTimeoutKey as CFString,
                NSNumber(value: 20)
            ), operation: "设置 20 秒上限")

            try manager.enable()
            guard manager.assertionID == id else {
                throw DiagnosticFailure(message: "重复开启不应创建另一份 assertion。")
            }

            guard let snapshot = try manager.snapshot(),
                  snapshot.isActive,
                  snapshot.type == (kIOPMAssertionTypePreventUserIdleSystemSleep as String) else {
                throw DiagnosticFailure(message: "系统没有确认预期的防闲置睡眠 assertion。")
            }
            print("CREATE/CHECK PASS: id=\(id), type=\(snapshot.type), level=\(snapshot.level)")
            try manager.disable()
            guard !manager.isEnabled, manager.assertionID == nil,
                  try manager.snapshot() == nil else {
                throw DiagnosticFailure(message: "释放后的管理器状态不正确。")
            }
            // A successfully released assertion should no longer be available from powerd.
            if let remaining = IOPMAssertionCopyProperties(id) {
                _ = remaining.takeRetainedValue()
                throw DiagnosticFailure(message: "释放后系统仍返回该 assertion。")
            }
            try manager.disable()
            print("RELEASE/CHECK PASS: own assertion removed")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exitCode = 1
        }
        // Explicit release before exit; other applications' assertions are never touched.
        if manager.isEnabled {
            do { try manager.disable() }
            catch {
                fputs("Cleanup: \(error.localizedDescription)\n", stderr)
                exitCode = 1
            }
        }
        exit(exitCode)
    }

    private static func check(_ result: IOReturn, operation: String) throws {
        guard result == kIOReturnSuccess else {
            throw AwakeAssertion.Failure(operation: operation, code: result)
        }
    }

    private struct DiagnosticFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
