import AppKit

ActionSettings.register()

// 隐藏自测入口：DropStation --selftest <图片路径>，验证图片处理引擎后直接退出
if let flagIndex = CommandLine.arguments.firstIndex(of: "--selftest"),
   flagIndex + 1 < CommandLine.arguments.count {
    FileActions.runSelfTest(imagePath: CommandLine.arguments[flagIndex + 1])
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
