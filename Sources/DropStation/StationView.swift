import AppKit

@MainActor
final class StationView: NSView, NSDraggingSource {
    var onSizeChange: ((NSSize) -> Void)?
    var onClose: (() -> Void)?

    private var files: [URL] = []
    private var iconCache: [URL: NSImage] = [:]
    private var fileSizeCache: [URL: String] = [:]
    private var pressedIndex: Int?
    private var pressPoint = NSPoint.zero
    private var activeDragIndex: Int?
    private var isMoveMode = false
    private var isToggleHovered = false
    private var actionHoverIndex: Int?
    private var hoveredIndex: Int?
    private var isCloseHovered = false
    private var didStartDrag = false
    private var trackingArea: NSTrackingArea?

    private let panelWidth: CGFloat = 360
    private let baseHeight: CGFloat = 360
    private let rowHeight: CGFloat = 58

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 20, yRadius: 20)
        NSColor(calibratedWhite: 0.10, alpha: 0.90).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()

        let title = files.isEmpty ? "文件中转站" : "文件中转站  ·  \(files.count)"
        drawText(title, at: NSPoint(x: 22, y: 18), font: .systemFont(ofSize: 15, weight: .semibold), color: .white)
        drawText("拖出文件即可发送或移动", at: NSPoint(x: 22, y: 42), font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.55))

        let closeRect = self.closeRect
        (isCloseHovered ? NSColor.white.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(ovalIn: closeRect).fill()
        drawText("×", at: NSPoint(x: closeRect.minX + 5.5, y: closeRect.minY + 1), font: .systemFont(ofSize: 16, weight: .medium), color: NSColor.white.withAlphaComponent(0.82))

        drawMoveToggle()

        if files.isEmpty {
            let dropRect = NSRect(x: 20, y: 88, width: bounds.width - 40, height: bounds.height - 110)
            NSColor.white.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: dropRect, xRadius: 16, yRadius: 16).fill()
            drawSymbol("arrow.down", centeredIn: NSRect(x: dropRect.midX - 15, y: dropRect.midY - 28, width: 30, height: 30), color: NSColor.white.withAlphaComponent(0.72))
            drawText("晃动正在拖动的文件，或拖到这里", centeredIn: NSRect(x: dropRect.minX, y: dropRect.midY + 18, width: dropRect.width, height: 22), font: .systemFont(ofSize: 12), color: NSColor.white.withAlphaComponent(0.7))
            return
        }

        for (index, fileURL) in files.enumerated() {
            let rect = rowRect(for: index)
            let cardRect = rect.insetBy(dx: 0, dy: 3)
            (hoveredIndex == index ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.055)).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12).fill()

            let iconRect = NSRect(x: 26, y: rect.minY + 7, width: 42, height: 42)
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: iconRect.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10).fill()
            icon(for: fileURL).draw(in: iconRect)
            drawText(fileURL.lastPathComponent, at: NSPoint(x: 82, y: rect.minY + 13), font: .systemFont(ofSize: 13, weight: .medium), color: .white, maxWidth: bounds.width - 136)
            drawText(fileSize(for: fileURL), at: NSPoint(x: 82, y: rect.minY + 33), font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.5))

            if hoveredIndex == index {
                let buttonRect = actionButtonRect(for: index)
                NSColor.white.withAlphaComponent(actionHoverIndex == index ? 0.26 : 0.14).setFill()
                NSBezierPath(ovalIn: buttonRect).fill()
                drawSymbol("ellipsis", centeredIn: buttonRect.insetBy(dx: 5, dy: 5), color: NSColor.white.withAlphaComponent(0.85))
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHoveredIndex = files.indices.first { rowRect(for: $0).contains(point) }
        let newCloseHovered = closeRect.contains(point)
        let newToggleHovered = moveToggleRect.contains(point)
        let newActionHover = files.indices.first { actionButtonRect(for: $0).contains(point) }
        guard newHoveredIndex != hoveredIndex
                || newCloseHovered != isCloseHovered
                || newToggleHovered != isToggleHovered
                || newActionHover != actionHoverIndex else { return }
        hoveredIndex = newHoveredIndex
        isCloseHovered = newCloseHovered
        isToggleHovered = newToggleHovered
        actionHoverIndex = newActionHover
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        isCloseHovered = false
        isToggleHovered = false
        actionHoverIndex = nil
        needsDisplay = true
    }

    func add(fileURLs newFileURLs: [URL]) {
        var added = false
        for fileURL in newFileURLs where !files.contains(fileURL) {
            files.append(fileURL)
            added = true
        }
        guard added else { return }
        refreshSize()
    }

    private func refreshSize() {
        let contentHeight = 72 + CGFloat(files.count) * rowHeight + 15
        let size = NSSize(width: panelWidth, height: max(baseHeight, contentHeight))
        setFrameSize(size)
        onSizeChange?(size)
        needsDisplay = true
    }

    func removeAll() {
        files.removeAll()
        hoveredIndex = nil
        iconCache.removeAll()
        fileSizeCache.removeAll()
        let size = NSSize(width: panelWidth, height: baseHeight)
        setFrameSize(size)
        onSizeChange?(size)
        needsDisplay = true
    }

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        canAccept(draggingInfo) ? .copy : []
    }

    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        canAccept(draggingInfo) ? .copy : []
    }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        let objects = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        add(fileURLs: objects.compactMap { ($0 as? NSURL)?.filePathURL })
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.contains(point) {
            onClose?()
            return
        }
        if moveToggleRect.contains(point) {
            isMoveMode.toggle()
            needsDisplay = true
            return
        }
        if let actionIndex = files.indices.first(where: { actionButtonRect(for: $0).contains(point) }) {
            showActionsMenu(for: actionIndex, at: point)
            return
        }
        pressedIndex = files.indices.first { rowRect(for: $0).contains(point) }
        pressPoint = point
        didStartDrag = false
        if pressedIndex == nil {
            window?.performDrag(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = files.indices.first(where: { rowRect(for: $0).contains(point) }) else { return }
        showActionsMenu(for: index, at: point)
    }

    private func showActionsMenu(for index: Int, at point: NSPoint) {
        guard files.indices.contains(index) else { return }
        let menu = NSMenu()

        func addItem(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }

        addItem("在访达中显示", #selector(revealInFinder(_:)))
        addItem("复制路径", #selector(copyPath(_:)))
        addItem("从面板移除", #selector(removeEntry(_:)))

        let fileURL = files[index]
        if FileActions.isImage(fileURL) {
            menu.addItem(.separator())
            addItem("压缩图片（\(ActionSettings.compressQuality)%）", #selector(compressImage(_:)))
            addItem("调整大小（≤\(ActionSettings.resizeMaxWidth)×\(ActionSettings.resizeMaxHeight)）", #selector(resizeImage(_:)))
            let ext = fileURL.pathExtension.lowercased()
            if ext != "jpg", ext != "jpeg" {
                addItem("转换为 JPEG（\(ActionSettings.convertQuality)%）", #selector(convertToJPEG(_:)))
            }
            if ext != "png" {
                addItem("转换为 PNG", #selector(convertToPNG(_:)))
            }
        }

        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard files.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([files[sender.tag]])
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard files.indices.contains(sender.tag) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(files[sender.tag].path, forType: .string)
    }

    @objc private func removeEntry(_ sender: NSMenuItem) {
        guard files.indices.contains(sender.tag) else { return }
        files.remove(at: sender.tag)
        hoveredIndex = nil
        actionHoverIndex = nil
        refreshSize()
    }

    @objc private func compressImage(_ sender: NSMenuItem) {
        runImageAction(at: sender.tag) { try FileActions.compressJPEG(at: $0, qualityPercent: ActionSettings.compressQuality) }
    }

    @objc private func resizeImage(_ sender: NSMenuItem) {
        runImageAction(at: sender.tag) { try FileActions.resize(at: $0, maxWidth: ActionSettings.resizeMaxWidth, maxHeight: ActionSettings.resizeMaxHeight) }
    }

    @objc private func convertToJPEG(_ sender: NSMenuItem) {
        runImageAction(at: sender.tag) { try FileActions.convert(at: $0, toJPEG: true, qualityPercent: ActionSettings.convertQuality) }
    }

    @objc private func convertToPNG(_ sender: NSMenuItem) {
        runImageAction(at: sender.tag) { try FileActions.convert(at: $0, toJPEG: false, qualityPercent: ActionSettings.convertQuality) }
    }

    /// 后台执行图片处理，成功后把面板条目就地替换为结果文件（原文件不动）
    private func runImageAction(at index: Int, _ work: @escaping @Sendable (URL) throws -> URL) {
        guard files.indices.contains(index) else { return }
        let sourceURL = files[index]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work(sourceURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let outputURL):
                    // 执行期间条目可能已被移除或顺序变化，按 URL 找回再替换
                    if let current = self.files.firstIndex(of: sourceURL) {
                        self.files[current] = outputURL
                        self.refreshSize()
                    }
                case .failure:
                    NSSound.beep()
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = pressedIndex, !didStartDrag, files.indices.contains(index) else { return }
        // 位移超过 4pt 才发起拖出，把点击时的轻微抖动排除掉
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - pressPoint.x
        let dy = point.y - pressPoint.y
        guard dx * dx + dy * dy >= 4 * 4 else { return }
        didStartDrag = true
        activeDragIndex = index
        let fileURL = files[index]
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let dragIconSize: CGFloat = 48
        let row = rowRect(for: index)
        let dragFrame = NSRect(x: row.minX + 4, y: row.midY - dragIconSize / 2, width: dragIconSize, height: dragIconSize)
        item.setDraggingFrame(dragFrame, contents: NSWorkspace.shared.icon(forFile: fileURL.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pressedIndex = nil
        didStartDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        isMoveMode ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // 移动模式下对方执行了移动，源文件已不在原位置，对应条目随之移除
        if isMoveMode, operation == .move, let index = activeDragIndex, files.indices.contains(index) {
            files.remove(at: index)
            hoveredIndex = nil
            refreshSize()
        }
        activeDragIndex = nil
        pressedIndex = nil
        didStartDrag = false
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.width - 38, y: 17, width: 22, height: 22)
    }

    private var moveToggleRect: NSRect {
        NSRect(x: bounds.width - 150, y: 17, width: 104, height: 22)
    }

    private func toggleSegmentRect(_ segment: Int) -> NSRect {
        NSRect(x: moveToggleRect.minX + 3 + CGFloat(segment) * 50, y: moveToggleRect.minY + 3, width: 48, height: 16)
    }

    private func drawMoveToggle() {
        let toggleRect = moveToggleRect
        NSColor.white.withAlphaComponent(isToggleHovered ? 0.12 : 0.08).setFill()
        NSBezierPath(roundedRect: toggleRect, xRadius: 11, yRadius: 11).fill()

        let selected = toggleSegmentRect(isMoveMode ? 1 : 0).insetBy(dx: -1, dy: -1)
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: selected, xRadius: 8, yRadius: 8).fill()

        drawText("复制", centeredIn: toggleSegmentRect(0),
                 font: .systemFont(ofSize: 11, weight: isMoveMode ? .regular : .semibold),
                 color: NSColor.white.withAlphaComponent(isMoveMode ? 0.45 : 0.9))
        drawText("移动", centeredIn: toggleSegmentRect(1),
                 font: .systemFont(ofSize: 11, weight: isMoveMode ? .semibold : .regular),
                 color: NSColor.white.withAlphaComponent(isMoveMode ? 0.9 : 0.45))
    }

    private func rowRect(for index: Int) -> NSRect {
        NSRect(x: 18, y: 72 + CGFloat(index) * rowHeight, width: bounds.width - 36, height: rowHeight)
    }

    private func actionButtonRect(for index: Int) -> NSRect {
        let row = rowRect(for: index)
        return NSRect(x: row.maxX - 32, y: row.midY - 13, width: 26, height: 26)
    }

    private func canAccept(_ draggingInfo: NSDraggingInfo) -> Bool {
        draggingInfo.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func icon(for fileURL: URL) -> NSImage {
        if let cached = iconCache[fileURL] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        iconCache[fileURL] = icon
        return icon
    }

    private func fileSize(for url: URL) -> String {
        if let cached = fileSizeCache[url] { return cached }
        let text: String
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 {
            if size < 1024 {
                text = "\(size) B"
            } else if size < 1024 * 1024 {
                text = String(format: "%.1f KB", Double(size) / 1024)
            } else if size < 1024 * 1024 * 1024 {
                text = String(format: "%.1f MB", Double(size) / 1024 / 1024)
            } else {
                text = String(format: "%.1f GB", Double(size) / 1024 / 1024 / 1024)
            }
        } else {
            text = "文件"
        }
        fileSizeCache[url] = text
        return text
    }

    private func drawSymbol(_ name: String, centeredIn rect: NSRect, color: NSColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) else { return }
        configured.draw(in: rect)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let maxWidth {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            attributes[.paragraphStyle] = paragraph
            (text as NSString).draw(in: NSRect(x: point.x, y: point.y, width: maxWidth, height: 20), withAttributes: attributes)
        } else {
            (text as NSString).draw(at: point, withAttributes: attributes)
        }
    }

    private func drawText(_ text: String, centeredIn rect: NSRect, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}
