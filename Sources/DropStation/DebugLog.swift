import Foundation

/// 轻量本地调试日志：写入 Application Support/DropStation/debug.log，
/// 用于定位第三方应用拖拽粘贴板类型与暂存失败原因。
enum DebugLog {
    private static let url = StagingStore.root
        .deletingLastPathComponent()
        .appendingPathComponent("debug.log")
    private static let maxBytes = 512 * 1024

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        truncateIfNeeded()
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func truncateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > maxBytes else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
