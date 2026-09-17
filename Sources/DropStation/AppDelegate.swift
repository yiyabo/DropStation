import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shakeDetector = ShakeDetector()
    private let station = StationWindowController()
    private var statusItem: NSStatusItem?
    private let keyboardShortcuts = KeyboardShortcutMonitor()
    private let permissionItem = NSMenuItem(title: "需要辅助功能权限…", action: nil, keyEquivalent: "")
    private let diskAccessItem = NSMenuItem(title: "完全磁盘访问权限…", action: nil, keyEquivalent: "")
    private lazy var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        StationSettings.register()
        do {
            try station.prepareForLaunch()
        } catch {
            NSLog("DropStation staging initialization failed: %@", error.localizedDescription)
        }

        // 启动时只检查权限，不主动弹出系统授权对话框；用户可从菜单栏入口手动打开设置。
        _ = AXIsProcessTrusted()

        keyboardShortcuts.onClose = { [weak self] in
            guard let self, self.station.isVisible else { return }
            self.station.dismissStation()
        }
        keyboardShortcuts.shouldInterceptEvent = { [weak self] in
            guard let self, let window = self.station.window else { return false }
            return window.frame.contains(NSEvent.mouseLocation)
        }
        station.onVisibilityChange = { [weak self] isVisible in
            self?.keyboardShortcuts.setEnabled(isVisible)
        }
        keyboardShortcuts.start()

        shakeDetector.onShake = { [weak self] fileURLs in
            guard let self else { return }
            self.station.add(fileURLs: fileURLs)
            self.station.show(near: NSEvent.mouseLocation)
        }
        shakeDetector.onShakePromise = { [weak self] receivers in
            guard let self else { return }
            self.station.add(promiseReceivers: receivers)
            self.station.show(near: NSEvent.mouseLocation)
        }
        shakeDetector.onShakeImage = { [weak self] data, ext, name in
            guard let self else { return }
            self.station.add(imageData: data, fileExtension: ext, suggestedName: name)
            self.station.show(near: NSEvent.mouseLocation)
        }

        shakeDetector.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { await self?.runUpdateCheck(manual: false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeDetector.stop()
        keyboardShortcuts.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.image?.accessibilityDescription = "文件中转站"
        item.button?.toolTip = "文件中转站"

        let menu = NSMenu()
        menu.delegate = self
        permissionItem.action = #selector(openAccessibilitySettings)
        permissionItem.target = self
        menu.addItem(permissionItem)
        diskAccessItem.action = #selector(openFullDiskSettings)
        diskAccessItem.target = self
        menu.addItem(diskAccessItem)
        menu.addItem(.separator())
        let showItem = NSMenuItem(title: "显示中转站", action: #selector(showStation), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let settingsItem = NSMenuItem(title: "动作设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 DropStation", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func showStation() {
        station.show(near: NSEvent.mouseLocation)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openFullDiskSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.reload()
        settingsWindow.window?.center()
        settingsWindow.showWindow(nil)
        settingsWindow.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func checkForUpdates() {
        Task { await runUpdateCheck(manual: true) }
    }

    private func runUpdateCheck(manual: Bool) async {
        switch await UpdateChecker.check() {
        case .updateAvailable(let release, let version):
            guard manual || UpdateChecker.skippedVersion != version else { return }
            presentUpdateAlert(release: release, version: version)
        case .upToDate:
            if manual {
                presentInfo(title: "已是最新版本", message: "当前版本 v\(UpdateChecker.currentVersion) 已是最新。")
            }
        case .failed(let message):
            DebugLog.write("update check failed: \(message)")
            if manual {
                presentInfo(title: "检查更新失败", message: message)
            }
        }
    }

    private func presentUpdateAlert(release: GitHubRelease, version: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(version)"
        let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = "当前版本 v\(UpdateChecker.currentVersion)。\n\n\(String(notes.prefix(400)))"
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "跳过此版本")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await downloadAndInstall(release: release, version: version) }
        case .alertThirdButtonReturn:
            UpdateChecker.skippedVersion = version
        default:
            break
        }
    }

    private func downloadAndInstall(release: GitHubRelease, version: String) async {
        let progressWindow = presentProgressWindow(title: "正在下载 \(version)…")
        do {
            try await UpdateInstaller.install(release: release)
            progressWindow?.close()
            presentRestartAlert(version: version)
        } catch {
            progressWindow?.close()
            DebugLog.write("update install failed: \(error.localizedDescription)")
            presentInfo(title: "更新失败", message: error.localizedDescription)
        }
    }

    private func presentRestartAlert(version: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(version) 已就绪"
        alert.informativeText = "重启 DropStation 以完成更新。"
        alert.addButton(withTitle: "立即重启")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func presentProgressWindow(title: String) -> NSWindow? {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 84),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        let indicator = NSProgressIndicator(frame: NSRect(x: 30, y: 30, width: 200, height: 20))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        window.contentView?.addSubview(indicator)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func presentInfo(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = AXIsProcessTrusted()
    }
}
