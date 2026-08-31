import AppKit

@MainActor
final class StationPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCloseEvent(event) {
            onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCloseEvent(event) {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    private func isCloseEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return true
        }
        return event.keyCode == 13 && event.modifierFlags.contains(.command)
    }
}
