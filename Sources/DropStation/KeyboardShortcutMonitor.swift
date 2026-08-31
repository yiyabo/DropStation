import AppKit
import CoreGraphics

private func dropStationKeyboardEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenableEventTap()
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown,
          monitor.isEnabledForEventTap,
          monitor.shouldInterceptEvent?() ?? false,
          KeyboardShortcutMonitor.isCloseEvent(event) else {
        return Unmanaged.passUnretained(event)
    }

    DispatchQueue.main.async { [weak monitor] in
        monitor?.onClose?()
    }
    return nil
}

final class KeyboardShortcutMonitor: @unchecked Sendable {
    var onClose: (() -> Void)?
    // 在事件 tap 回调（主线程）里同步调用；只有返回 true 时才拦截并吞掉按键。
    var shouldInterceptEvent: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    fileprivate var isEnabledForEventTap = false

    func start() {
        guard eventTap == nil else { return }
        installEventTap()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabledForEventTap = enabled
    }

    func stop() {
        isEnabledForEventTap = false
        retryTimer?.invalidate()
        retryTimer = nil

        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
    }

    fileprivate func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        guard AXIsProcessTrusted() else {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.installEventTap()
            }
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil

        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: dropStationKeyboardEventTapCallback,
            userInfo: userInfo
        ) else {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                self?.installEventTap()
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate static func isCloseEvent(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 {
            return true
        }
        return keyCode == 13 && event.flags.contains(.maskCommand)
    }
}
