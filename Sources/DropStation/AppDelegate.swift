import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let shakeDetector = ShakeDetector()
    private let station = StationWindowController()
    private var statusItem: NSStatusItem?
    private let keyboardShortcuts = KeyboardShortcutMonitor()
    private let permissionItem = NSMenuItem(title: "需要辅助功能权限…", action: nil, keyEquivalent: "")
    private lazy var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

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

        shakeDetector.start()
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
        menu.addItem(.separator())
        let showItem = NSMenuItem(title: "显示中转站", action: #selector(showStation), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let settingsItem = NSMenuItem(title: "动作设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
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
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = AXIsProcessTrusted()
    }
}
