import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let awake = AwakeAssertion(reason: "KeepAwake - allow locked background tasks")
    private var item: NSStatusItem!
    private var window: NSWindow?
    private var stateLabel: NSTextField?
    private var stateImage: NSImageView?
    private var toggleButton: NSButton?
    private var errorMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let currentApplication = NSRunningApplication.current
            let currentPID = currentApplication.processIdentifier
            let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { $0.processIdentifier != currentPID }
            // Both instances elect the earlier launch; PID breaks ties without a mutual-exit race.
            if otherInstances.contains(where: { other in
                if let otherDate = other.launchDate, let currentDate = currentApplication.launchDate,
                   otherDate != currentDate {
                    return otherDate < currentDate
                }
                return other.processIdentifier < currentPID
            }) {
                NSApp.terminate(nil)
                return
            }
        }
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        addMenuItem(applicationMenu, title: "查看状态", action: #selector(showStatus))
        let quitEntry = addMenuItem(applicationMenu, title: "退出保持清醒", action: #selector(quit))
        quitEntry.keyEquivalent = "q"
        let rootEntry = NSMenuItem()
        rootEntry.submenu = applicationMenu
        mainMenu.addItem(rootEntry)
        NSApp.mainMenu = mainMenu
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "KeepAwakeCoffee"
        item.isVisible = true
        item.behavior = [.removalAllowed, .terminationOnRemoval]
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 11, weight: .semibold)
        }
        updateAppearance()
        if !UserDefaults.standard.bool(forKey: "HasShownIntroduction") {
            showStatus()
            UserDefaults.standard.set(true, forKey: "HasShownIntroduction")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        item?.isVisible = true
        showStatus()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try awake.disable()
            return .terminateNow
        } catch {
            // Process termination also releases its power assertions.
            return .terminateNow
        }
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggleAwake()
        }
    }

    @objc private func toggleAwake() {
        do {
            try awake.toggle()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
        updateAppearance()
    }

    private func coffeeImage(enabled: Bool, size: CGFloat = 19) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let base = NSImage(systemSymbolName: enabled ? "cup.and.heat.waves.fill" : "cup.and.saucer", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: enabled ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: nil)
            base?.draw(in: NSRect(x: 2, y: 2, width: 18, height: 18))
            if !enabled {
                // A slash distinguishes OFF even on monochrome or low-contrast menu bars.
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3, y: 20))
                slash.line(to: NSPoint(x: 20, y: 3))
                slash.lineWidth = 2
                slash.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.size = NSSize(width: size, height: size)
        return image
    }

    private func updateAppearance() {
        let enabled = awake.isEnabled
        let label = enabled ? "保持清醒：已开启" : "保持清醒：已关闭"
        if let button = item?.button {
            button.image = coffeeImage(enabled: enabled)
            button.title = (enabled ? "开" : "关") + (errorMessage == nil ? "" : " !")
            button.toolTip = errorMessage.map { "操作未完成：\($0)。右键查看状态。" }
                ?? "\(label)\n单击\(enabled ? "关闭" : "开启") · 右键更多选项"
            button.setAccessibilityLabel(label)
            button.setAccessibilityValue(errorMessage.map { "\(enabled ? "开" : "关")；\($0)" } ?? (enabled ? "开" : "关"))
            button.setAccessibilityHelp("单击直接切换保持清醒；右键显示更多选项。")
        }
        let state = enabled ? "已开启 · 可以锁屏和息屏" : "已关闭 · 本工具未阻止自动睡眠"
        stateLabel?.stringValue = state + (errorMessage.map { "\n操作未完成：\($0)" } ?? "")
        stateImage?.image = coffeeImage(enabled: enabled, size: 44)
        toggleButton?.title = enabled ? "关闭保持清醒" : "开启保持清醒"
    }

    private func showMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: awake.isEnabled ? "已开启 · 可以锁屏和息屏" : "已关闭 · 本工具未阻止自动睡眠", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        addMenuItem(menu, title: awake.isEnabled ? "关闭保持清醒" : "开启保持清醒", action: #selector(toggleAwake))
        addMenuItem(menu, title: "查看状态", action: #selector(showStatus))
        let loginStatus = SMAppService.mainApp.status
        let login = addMenuItem(menu, title: loginStatus == .requiresApproval ? "登录时打开（等待系统允许）" : "登录时打开", action: #selector(toggleLogin))
        login.state = loginStatus == .enabled ? .on : (loginStatus == .requiresApproval ? .mixed : .off)
        menu.addItem(.separator())
        addMenuItem(menu, title: "退出保持清醒", action: #selector(quit))
        item.menu = menu
        defer { item.menu = nil }
        item.button?.performClick(nil)
    }

    @discardableResult private func addMenuItem(_ menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            errorMessage = nil
            if SMAppService.mainApp.status == .requiresApproval {
                errorMessage = "请在系统设置的登录项中允许保持清醒。"
                showStatus()
            }
        } catch {
            errorMessage = "登录时打开设置失败：\(error.localizedDescription)"
            showStatus()
        }
        updateAppearance()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func hideStatus() { window?.orderOut(nil) }

    @objc private func showStatus() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "保持清醒"
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            let content = NSStackView()
            content.orientation = .vertical
            content.alignment = .centerX
            content.spacing = 15
            content.translatesAutoresizingMaskIntoConstraints = false
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
            content.addArrangedSubview(icon)
            stateImage = icon
            let state = NSTextField(wrappingLabelWithString: "")
            state.font = .systemFont(ofSize: 17, weight: .semibold)
            state.alignment = .center
            state.maximumNumberOfLines = 3
            content.addArrangedSubview(state)
            stateLabel = state
            let guide = NSTextField(wrappingLabelWithString: "单击菜单栏的咖啡杯，立即开启或关闭。\n带斜杠的杯子＋关：已关闭；正常杯子＋开：已开启。")
            guide.font = .systemFont(ofSize: 12)
            guide.textColor = .secondaryLabelColor
            guide.alignment = .center
            content.addArrangedSubview(guide)
            let toggle = NSButton(title: "开启保持清醒", target: self, action: #selector(toggleAwake))
            toggle.bezelStyle = .rounded
            content.addArrangedSubview(toggle)
            toggleButton = toggle
            let hide = NSButton(title: "收起到菜单栏", target: self, action: #selector(hideStatus))
            hide.bezelStyle = .rounded
            content.addArrangedSubview(hide)
            panel.contentView!.addSubview(content)
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
                content.widthAnchor.constraint(equalToConstant: 384)
            ])
            panel.center()
            window = panel
        }
        updateAppearance()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct KeepAwakeApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
