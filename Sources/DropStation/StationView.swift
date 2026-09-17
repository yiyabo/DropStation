import AppKit

@MainActor
final class StationView: NSView, NSDraggingSource {
    var onSizeChange: ((NSSize) -> Void)?
    var onClose: (() -> Void)?

    private let stagingStore = StagingStore()
    private var files: [StagedItem] = []
    private var iconCache: [URL: NSImage] = [:]
    private var fileSizeCache: [URL: String] = [:]
    private var pendingImports: Set<UUID> = []
    private var isAcceptingFiles = true
    private var lastImportError: String?
    private var pressedID: UUID?
    private var pressPoint = NSPoint.zero
    private var activeDragID: UUID?
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
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepareForLaunch() throws {
        files = try stagingStore.prepareForLaunch()
        isAcceptingFiles = true
        refreshSize()
    }

    func willShow() {
        isAcceptingFiles = true
    }

    func willDismiss() {
        isAcceptingFiles = false
        activeDragID = nil
        pressedID = nil
        if StationSettings.closeRetention == .discardImmediately {
            stagingStore.discardAll()
            files.removeAll()
            iconCache.removeAll()
            fileSizeCache.removeAll()
            refreshSize()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 20, yRadius: 20)
        NSColor(calibratedWhite: 0.10, alpha: 0.90).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()

        let totalCount = files.count + pendingImports.count
        let title = totalCount == 0 ? "文件中转站" : "文件中转站  ·  \(totalCount)"
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
            let hint: String
            if !pendingImports.isEmpty {
                hint = "正在安全暂存 \(pendingImports.count) 个文件…"
            } else if let lastImportError {
                hint = lastImportError
            } else {
                hint = "晃动正在拖动的文件，或拖到这里"
            }
            drawText(hint, centeredIn: NSRect(x: dropRect.minX, y: dropRect.midY + 18, width: dropRect.width, height: 22), font: .systemFont(ofSize: 12), color: NSColor.white.withAlphaComponent(0.7))
            return
        }

        for (index, item) in files.enumerated() {
            let rect = rowRect(for: index)
            let cardRect = rect.insetBy(dx: 0, dy: 3)
            (hoveredIndex == index ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.055)).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12).fill()
            let iconRect = NSRect(x: 26, y: rect.minY + 7, width: 42, height: 42)
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: iconRect.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10).fill()
            icon(for: item.stagedURL).draw(in: iconRect)
            drawText(item.displayName, at: NSPoint(x: 82, y: rect.minY + 13), font: .systemFont(ofSize: 13, weight: .medium), color: .white, maxWidth: bounds.width - 136)
            drawText(fileSize(for: item.stagedURL), at: NSPoint(x: 82, y: rect.minY + 33), font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.5))
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
        if let trackingArea { removeTrackingArea(trackingArea) }
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
        guard newHoveredIndex != hoveredIndex || newCloseHovered != isCloseHovered || newToggleHovered != isToggleHovered || newActionHover != actionHoverIndex else { return }
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

    func add(fileURLs sourceURLs: [URL]) {
        guard isAcceptingFiles else { return }
        var seen = Set<URL>()
        let uniqueSources = sourceURLs.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        guard !uniqueSources.isEmpty else { return }
        let batchID = UUID()
        pendingImports.insert(batchID)
        lastImportError = nil
        needsDisplay = true
        Task {
            let batch = await stagingStore.stage(uniqueSources)
            pendingImports.remove(batchID)
            guard isAcceptingFiles || StationSettings.closeRetention == .retainForThreeDays else {
                stagingStore.removeAll(batch.items)
                return
            }
            files.append(contentsOf: batch.items)
            lastImportError = batch.failures.isEmpty ? nil : "无法读取部分来源文件"
            refreshSize()
            if !batch.failures.isEmpty { NSSound.beep() }
        }
    }

    private func refreshSize() {
        let contentHeight = 72 + CGFloat(files.count) * rowHeight + 15
        let size = NSSize(width: panelWidth, height: max(baseHeight, contentHeight))
        setFrameSize(size)
        onSizeChange?(size)
        needsDisplay = true
    }

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation { canAccept(draggingInfo) ? .copy : [] }
    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation { canAccept(draggingInfo) ? .copy : [] }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        let pasteboard = draggingInfo.draggingPasteboard
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let urls = objects.compactMap { ($0 as? NSURL)?.filePathURL }
        if !urls.isEmpty {
            add(fileURLs: urls)
            return true
        }

        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        guard !receivers.isEmpty, let destination = try? stagingStore.promiseReceivingDirectory() else { return false }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        pendingImports.insert(UUID())
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { [weak self] fileURL, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if error == nil {
                        self.add(fileURLs: [fileURL])
                    } else {
                        self.lastImportError = "无法读取微信临时文件"
                        self.needsDisplay = true
                        NSSound.beep()
                    }
                }
            }
        }
        queue.addBarrierBlock { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingImports.removeAll()
                self.stagingStore.removeIncomingDirectory(destination)
                self.needsDisplay = true
            }
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.contains(point) { onClose?(); return }
        if moveToggleRect.contains(point) { isMoveMode.toggle(); needsDisplay = true; return }
        if let index = files.indices.first(where: { actionButtonRect(for: $0).contains(point) }) { showActionsMenu(for: index, at: point); return }
        if let index = files.indices.first(where: { rowRect(for: $0).contains(point) }) {
            pressedID = files[index].id
            pressPoint = point
            didStartDrag = false
        } else {
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
        let item = files[index]
        let menu = NSMenu()
        func addItem(_ title: String, _ action: Selector) {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = item.id.uuidString
            menu.addItem(menuItem)
        }
        addItem("在访达中显示", #selector(revealInFinder(_:)))
        addItem("复制路径", #selector(copyPath(_:)))
        addItem("从面板移除", #selector(removeEntry(_:)))
        if FileActions.isImage(item.stagedURL) {
            menu.addItem(.separator())
            addItem("压缩图片（\(ActionSettings.compressQuality)%）", #selector(compressImage(_:)))
            addItem("调整大小（≤\(ActionSettings.resizeMaxWidth)×\(ActionSettings.resizeMaxHeight)）", #selector(resizeImage(_:)))
            let ext = item.stagedURL.pathExtension.lowercased()
            if ext != "jpg", ext != "jpeg" { addItem("转换为 JPEG（\(ActionSettings.convertQuality)%）", #selector(convertToJPEG(_:))) }
            if ext != "png" { addItem("转换为 PNG", #selector(convertToPNG(_:))) }
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func item(for sender: NSMenuItem) -> StagedItem? {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return nil }
        return files.first { $0.id == id }
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) { if let item = item(for: sender) { NSWorkspace.shared.activateFileViewerSelecting([item.stagedURL]) } }
    @objc private func copyPath(_ sender: NSMenuItem) { if let item = item(for: sender) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.stagedURL.path, forType: .string) } }
    @objc private func removeEntry(_ sender: NSMenuItem) { if let item = item(for: sender) { remove(item) } }
    @objc private func compressImage(_ sender: NSMenuItem) { if let item = item(for: sender) { runImageAction(item) { try FileActions.compressJPEG(at: $0, qualityPercent: ActionSettings.compressQuality) } } }
    @objc private func resizeImage(_ sender: NSMenuItem) { if let item = item(for: sender) { runImageAction(item) { try FileActions.resize(at: $0, maxWidth: ActionSettings.resizeMaxWidth, maxHeight: ActionSettings.resizeMaxHeight) } } }
    @objc private func convertToJPEG(_ sender: NSMenuItem) { if let item = item(for: sender) { runImageAction(item) { try FileActions.convert(at: $0, toJPEG: true, qualityPercent: ActionSettings.convertQuality) } } }
    @objc private func convertToPNG(_ sender: NSMenuItem) { if let item = item(for: sender) { runImageAction(item) { try FileActions.convert(at: $0, toJPEG: false, qualityPercent: ActionSettings.convertQuality) } } }

    private func remove(_ item: StagedItem) {
        stagingStore.remove(item)
        files.removeAll { $0.id == item.id }
        iconCache.removeValue(forKey: item.stagedURL)
        fileSizeCache.removeValue(forKey: item.stagedURL)
        refreshSize()
    }

    private func runImageAction(_ item: StagedItem, _ work: @escaping @Sendable (URL) throws -> URL) {
        let sourceURL = item.stagedURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work(sourceURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let outputURL):
                    guard self.files.contains(where: { $0.id == item.id }),
                          let updated = self.stagingStore.replace(item, with: outputURL) else {
                        try? FileManager.default.removeItem(at: outputURL)
                        return
                    }
                    if let index = self.files.firstIndex(where: { $0.id == item.id }) { self.files[index] = updated }
                    self.iconCache.removeValue(forKey: sourceURL)
                    self.fileSizeCache.removeValue(forKey: sourceURL)
                    self.refreshSize()
                case .failure:
                    NSSound.beep()
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = pressedID, !didStartDrag, let index = files.firstIndex(where: { $0.id == id }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - pressPoint.x, dy = point.y - pressPoint.y
        guard dx * dx + dy * dy >= 16 else { return }
        didStartDrag = true
        activeDragID = id
        let item = files[index]
        let dragItem = NSDraggingItem(pasteboardWriter: item.stagedURL as NSURL)
        let row = rowRect(for: index)
        let dragFrame = NSRect(x: row.minX + 4, y: row.midY - 24, width: 48, height: 48)
        dragItem.setDraggingFrame(dragFrame, contents: NSWorkspace.shared.icon(forFile: item.stagedURL.path))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { pressedID = nil; didStartDrag = false }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { isMoveMode ? .move : .copy }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if isMoveMode, operation == .move, let id = activeDragID, let item = files.first(where: { $0.id == id }) {
            stagingStore.remove(item)
            files.removeAll { $0.id == id }
            refreshSize()
        }
        activeDragID = nil
        pressedID = nil
        didStartDrag = false
    }

    private var closeRect: NSRect { NSRect(x: bounds.width - 38, y: 17, width: 22, height: 22) }
    private var moveToggleRect: NSRect { NSRect(x: bounds.width - 150, y: 17, width: 104, height: 22) }
    private func toggleSegmentRect(_ segment: Int) -> NSRect { NSRect(x: moveToggleRect.minX + 3 + CGFloat(segment) * 50, y: moveToggleRect.minY + 3, width: 48, height: 16) }

    private func drawMoveToggle() {
        NSColor.white.withAlphaComponent(isToggleHovered ? 0.12 : 0.08).setFill()
        NSBezierPath(roundedRect: moveToggleRect, xRadius: 11, yRadius: 11).fill()
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: toggleSegmentRect(isMoveMode ? 1 : 0).insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8).fill()
        drawText("复制", centeredIn: toggleSegmentRect(0), font: .systemFont(ofSize: 11, weight: isMoveMode ? .regular : .semibold), color: NSColor.white.withAlphaComponent(isMoveMode ? 0.45 : 0.9))
        drawText("移动", centeredIn: toggleSegmentRect(1), font: .systemFont(ofSize: 11, weight: isMoveMode ? .semibold : .regular), color: NSColor.white.withAlphaComponent(isMoveMode ? 0.9 : 0.45))
    }

    private func rowRect(for index: Int) -> NSRect { NSRect(x: 18, y: 72 + CGFloat(index) * rowHeight, width: bounds.width - 36, height: rowHeight) }
    private func actionButtonRect(for index: Int) -> NSRect { let row = rowRect(for: index); return NSRect(x: row.maxX - 32, y: row.midY - 13, width: 26, height: 26) }
    private func canAccept(_ info: NSDraggingInfo) -> Bool { info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) }

    private func icon(for url: URL) -> NSImage {
        if let cached = iconCache[url] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url] = icon
        return icon
    }

    private func fileSize(for url: URL) -> String {
        if let cached = fileSizeCache[url] { return cached }
        let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        let text: String
        switch size {
        case let value? where value < 1024: text = "\(value) B"
        case let value? where value < 1_048_576: text = String(format: "%.1f KB", Double(value) / 1024)
        case let value? where value < 1_073_741_824: text = String(format: "%.1f MB", Double(value) / 1_048_576)
        case let value?: text = String(format: "%.1f GB", Double(value) / 1_073_741_824)
        case nil: text = "文件"
        }
        fileSizeCache[url] = text
        return text
    }

    private func drawSymbol(_ name: String, centeredIn rect: NSRect, color: NSColor) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil), let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color])) else { return }
        configured.draw(in: rect)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let maxWidth {
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; attributes[.paragraphStyle] = paragraph
            (text as NSString).draw(in: NSRect(x: point.x, y: point.y, width: maxWidth, height: 20), withAttributes: attributes)
        } else { (text as NSString).draw(at: point, withAttributes: attributes) }
    }

    private func drawText(_ text: String, centeredIn rect: NSRect, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}
