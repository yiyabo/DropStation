import AppKit

@MainActor
final class ShakeDetector {
    var onShake: (([URL]) -> Void)?
    var onShakePromise: (([NSFilePromiseReceiver]) -> Void)?
    var onShakeImage: ((Data, String, String?) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPotentialDrag = false
    private var isFileDrag = false
    private var dragChangeCountBaseline = 0
    private var startedAt: TimeInterval = 0
    private var lastPoint = NSPoint.zero
    private var lastAxis: Axis?
    private var lastDirection = 0
    private var reversals = 0
    private var hasTriggered = false

    private enum Axis {
        case horizontal
        case vertical
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            reset()
            isPotentialDrag = true
            lastPoint = NSEvent.mouseLocation
            dragChangeCountBaseline = NSPasteboard(name: .drag).changeCount

        case .leftMouseDragged:
            guard isPotentialDrag, !hasTriggered else { return }
            let point = NSEvent.mouseLocation

            if !isFileDrag {
                guard hasDraggedFile else { return }
                isFileDrag = true
                startedAt = event.timestamp
            }

            updateDirection(with: point, timestamp: event.timestamp)
            lastPoint = point

        case .leftMouseUp:
            reset()

        default:
            break
        }
    }

    // 拖拽粘贴板的内容在拖拽会话结束后仍会残留，只有 changeCount 相对按下鼠标时
    // 前进了，才说明出现了新的拖拽会话，避免把框选、拖动窗口误判成拖文件。
    private var hasDraggedFile: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount > dragChangeCountBaseline else { return false }
        let hasFileURLs = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        let hasPromises = pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
        return hasFileURLs || hasPromises || PasteboardImage.hasImageData(pasteboard)
    }

    private func updateDirection(with point: NSPoint, timestamp: TimeInterval) {
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        let axis: Axis
        let distance: CGFloat

        if abs(dx) >= abs(dy) {
            axis = .horizontal
            distance = abs(dx)
        } else {
            axis = .vertical
            distance = abs(dy)
        }

        guard distance >= 4 else { return }
        let direction = axis == .horizontal ? (dx > 0 ? 1 : -1) : (dy > 0 ? 1 : -1)

        if lastAxis == axis, lastDirection != 0, direction != lastDirection {
            reversals += 1
        } else if lastAxis != axis {
            reversals = 0
        }

        lastAxis = axis
        lastDirection = direction

        let elapsed = timestamp - startedAt
        if reversals >= 3, elapsed <= 1.2 {
            trigger()
        } else if elapsed > 1.2 {
            startedAt = timestamp
            reversals = 0
            lastAxis = nil
            lastDirection = 0
        }
    }

    private func trigger() {
        // 微信等应用通过 file promise 提供文件：优先走 promise 接收，让来源安全落地；
        // 普通拖拽（Finder 等）没有 promise，回退到直接读文件 URL。
        let pasteboard = NSPasteboard(name: .drag)
        DebugLog.write("shake trigger, pasteboard types=\(pasteboard.types ?? [])")
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        if !receivers.isEmpty {
            hasTriggered = true
            onShakePromise?(receivers)
            return
        }

        let fileURLs = draggedFileURLs
        // 微信图片查看器会给一个无法真实打开的容器路径：先探测可读性，
        // 读不了就改取粘贴板里的位图数据，自己落成暂存文件。
        if let first = fileURLs.first, Self.probeReadable(first) {
            hasTriggered = true
            onShake?(fileURLs)
            return
        }
        if let image = PasteboardImage.payload(from: pasteboard) {
            hasTriggered = true
            let name = fileURLs.first?.deletingPathExtension().lastPathComponent
            onShakeImage?(image.data, image.fileExtension, name)
            return
        }

        guard !fileURLs.isEmpty else { return }
        hasTriggered = true
        onShake?(fileURLs)
    }

    private static func probeReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        try? handle.close()
        return true
    }

    private var draggedFileURLs: [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { ($0 as? NSURL)?.filePathURL }
    }

    private func reset() {
        isPotentialDrag = false
        isFileDrag = false
        dragChangeCountBaseline = 0
        startedAt = 0
        lastAxis = nil
        lastDirection = 0
        reversals = 0
        hasTriggered = false
    }
}
