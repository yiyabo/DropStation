import AppKit

/// 「动作设置」窗口：调整三个内置图片动作的预设参数，改动即时生效（写 UserDefaults）。
@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    private let compressQualityField = NSTextField()
    private let maxWidthField = NSTextField()
    private let maxHeightField = NSTextField()
    private let formatPopup = NSPopUpButton()
    private let convertQualityField = NSTextField()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "动作设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 每次打开前刷新为 UserDefaults 里的当前值
    func reload() {
        compressQualityField.integerValue = ActionSettings.compressQuality
        maxWidthField.integerValue = ActionSettings.resizeMaxWidth
        maxHeightField.integerValue = ActionSettings.resizeMaxHeight
        formatPopup.selectItem(withTitle: ActionSettings.convertFormat)
        convertQualityField.integerValue = ActionSettings.convertQuality
        convertQualityField.isEnabled = ActionSettings.convertFormat == "JPEG"
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        func sectionLabel(_ text: String, y: CGFloat) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.frame = NSRect(x: 20, y: y, width: 200, height: 18)
            content.addSubview(label)
        }

        func fieldLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 76) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 12)
            label.frame = NSRect(x: x, y: y + 3, width: width, height: 16)
            content.addSubview(label)
        }

        func numberField(_ field: NSTextField, x: CGFloat, y: CGFloat, minimum: Int, maximum: Int) {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: minimum)
            formatter.maximum = NSNumber(value: maximum)
            field.formatter = formatter
            field.alignment = .right
            field.font = .systemFont(ofSize: 12)
            field.frame = NSRect(x: x, y: y, width: 60, height: 24)
            field.delegate = self
            content.addSubview(field)
        }

        sectionLabel("压缩图片", y: 258)
        fieldLabel("质量", x: 36, y: 230)
        numberField(compressQualityField, x: 116, y: 228, minimum: 1, maximum: 100)
        fieldLabel("%（输出 JPEG）", x: 184, y: 230, width: 140)

        sectionLabel("调整图片大小", y: 192)
        fieldLabel("最大宽度", x: 36, y: 164)
        numberField(maxWidthField, x: 116, y: 162, minimum: 16, maximum: 8192)
        fieldLabel("px", x: 182, y: 164, width: 20)
        fieldLabel("最大高度", x: 208, y: 164)
        numberField(maxHeightField, x: 288, y: 162, minimum: 16, maximum: 8192)
        fieldLabel("px", x: 354, y: 164, width: 20)

        sectionLabel("转换图片", y: 126)
        fieldLabel("格式", x: 36, y: 96)
        formatPopup.addItems(withTitles: ["JPEG", "PNG"])
        formatPopup.font = .systemFont(ofSize: 12)
        formatPopup.frame = NSRect(x: 112, y: 94, width: 92, height: 26)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        content.addSubview(formatPopup)
        fieldLabel("质量", x: 224, y: 96)
        numberField(convertQualityField, x: 268, y: 94, minimum: 1, maximum: 100)
        fieldLabel("%", x: 334, y: 96, width: 16)

        let hint = NSTextField(wrappingLabelWithString: "以上参数即时生效。右键点击面板中的文件行，或悬停后点击行尾按钮即可使用这些动作。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 22, width: 340, height: 40)
        content.addSubview(hint)
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let format = sender.titleOfSelectedItem ?? "JPEG"
        ActionSettings.convertFormat = format
        convertQualityField.isEnabled = format == "JPEG"
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        switch field {
        case compressQualityField:
            ActionSettings.compressQuality = clamp(field.integerValue, min: 1, max: 100)
            field.integerValue = ActionSettings.compressQuality
        case maxWidthField:
            ActionSettings.resizeMaxWidth = clamp(field.integerValue, min: 16, max: 8192)
            field.integerValue = ActionSettings.resizeMaxWidth
        case maxHeightField:
            ActionSettings.resizeMaxHeight = clamp(field.integerValue, min: 16, max: 8192)
            field.integerValue = ActionSettings.resizeMaxHeight
        case convertQualityField:
            ActionSettings.convertQuality = clamp(field.integerValue, min: 1, max: 100)
            field.integerValue = ActionSettings.convertQuality
        default:
            break
        }
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }
}
