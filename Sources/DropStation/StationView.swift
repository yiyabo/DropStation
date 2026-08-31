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
            drawText(fileURL.lastPathComponent, at: NSPoint(x: 82, y: rect.minY + 13), font: .systemFont(ofSize: 13, weight: .medium), color: .white, maxWidth: bounds.width - 104)
            drawText(fileSize(for: fileURL), at: NSPoint(x: 82, y: rect.minY + 33), font: .systemFont(ofSize: 11), color: NSColor.white.withAlphaComponent(0.5))
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
        guard newHoveredIndex != hoveredIndex || newCloseHovered != isCloseHovered else { return }
        hoveredIndex = newHoveredIndex
        isCloseHovered = newCloseHovered
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        isCloseHovered = false
        needsDisplay = true
    }

    func add(fileURL: URL) {
        guard !files.contains(fileURL) else { return }
        files.append(fileURL)
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
        objects.compactMap { ($0 as? NSURL)?.filePathURL }.forEach { add(fileURL: $0) }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.contains(point) {
            onClose?()
            return
        }
        pressedIndex = files.indices.first { rowRect(for: $0).contains(point) }
        pressPoint = point
        didStartDrag = false
        if pressedIndex == nil {
            window?.performDrag(with: event)
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
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pressedIndex = nil
        didStartDrag = false
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.width - 38, y: 17, width: 22, height: 22)
    }

    private func rowRect(for index: Int) -> NSRect {
        NSRect(x: 18, y: 72 + CGFloat(index) * rowHeight, width: bounds.width - 36, height: rowHeight)
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
