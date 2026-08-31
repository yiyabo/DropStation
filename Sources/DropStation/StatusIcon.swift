import AppKit

enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 14), xRadius: 3.5, yRadius: 3.5).fill()

            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: NSRect(x: 6.5, y: 6.5, width: 5, height: 5), xRadius: 1.2, yRadius: 1.2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
