import AppKit
import QuartzCore

@MainActor
final class StationWindowController: NSWindowController {
    var onVisibilityChange: ((Bool) -> Void)?
    private let stationView: StationView
    private var hasStoredPosition = false

    // Keep the panel alive while it is hidden so its position remains stable.

    init() {
        stationView = StationView(frame: NSRect(x: 0, y: 0, width: 360, height: 360))

        let panel = StationPanel(
            contentRect: stationView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = stationView
        panel.acceptsMouseMovedEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true

        super.init(window: panel)
        panel.onClose = { [weak self] in
            self?.dismissStation()
        }
        stationView.onSizeChange = { [weak self] size in
            self?.resize(to: size)
        }
        stationView.onClose = { [weak self] in
            self?.dismissStation()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func prepareForLaunch() throws {
        try stationView.prepareForLaunch()
    }

    func add(fileURLs: [URL]) {
        stationView.add(fileURLs: fileURLs)
    }

    func dismissStation() {
        stationView.willDismiss()
        window?.orderOut(nil)
        onVisibilityChange?(false)
    }

    func show(near point: NSPoint) {
        guard let window else { return }
        stationView.willShow()
        onVisibilityChange?(true)
        let size = window.frame.size
        var origin = window.frame.origin

        // 记忆的位置可能因拔掉显示器等原因落到所有屏幕之外，此时放弃记忆重新就近定位
        if hasStoredPosition, !NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: origin, size: size)) }) {
            hasStoredPosition = false
        }

        if !hasStoredPosition {
            let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
            let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            origin = NSPoint(x: point.x + 18, y: point.y - size.height - 18)

            if origin.x + size.width > visibleFrame.maxX {
                origin.x = point.x - size.width - 18
            }
            if origin.y < visibleFrame.minY {
                origin.y = point.y + 18
            }
            origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - size.width - 8))
            origin.y = max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - size.height - 8))
            hasStoredPosition = true
        }
        let targetFrame = NSRect(origin: origin, size: size)

        if !window.isVisible {
            let startSize = NSSize(width: size.width * 0.94, height: size.height * 0.94)
            let startOrigin = NSPoint(x: origin.x + (size.width - startSize.width) / 2, y: origin.y + (size.height - startSize.height) / 2)
            window.setFrame(NSRect(origin: startOrigin, size: startSize), display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            window.makeKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1
            }
        } else {
            window.setFrameOrigin(origin)
        }
    }

    private func resize(to size: NSSize) {
        guard let window else { return }
        var frame = window.frame
        let top = frame.maxY
        frame.size = size
        // 文件多到长高时总高度不超过屏幕可见区域，超出底部时整体上移夹回
        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.size.height = min(frame.size.height, visibleFrame.height)
            frame.size.width = min(frame.size.width, visibleFrame.width)
        }
        frame.origin.y = top - frame.size.height
        if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame, frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }
        window.setFrame(frame, display: true)
    }
}
