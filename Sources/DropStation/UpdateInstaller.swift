import AppKit
import CryptoKit
import Foundation

/// 下载 GitHub Release 中的 DMG，校验 SHA256 后挂载取出应用，
/// 通过退出后执行的辅助脚本完成替换并重启。
enum UpdateInstaller {

    enum InstallError: LocalizedError {
        case noAsset
        case downloadFailed
        case checksumMismatch
        case mountFailed
        case appMissing
        case targetNotWritable

        var errorDescription: String? {
            switch self {
            case .noAsset: "Release 中没有找到 DMG 资产"
            case .downloadFailed: "下载更新包失败"
            case .checksumMismatch: "更新包校验和不匹配，已中止安装"
            case .mountFailed: "无法挂载更新镜像"
            case .appMissing: "更新镜像中没有找到应用"
            case .targetNotWritable: "当前应用所在目录不可写，无法替换"
            }
        }
    }

    static func install(release: GitHubRelease) async throws {
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw InstallError.noAsset
        }
        let dmgURL = try await download(dmgAsset.browserDownloadURL)

        if let checksumAsset = release.assets.first(where: { $0.name.hasSuffix(".sha256") }) {
            let checksumURL = try await download(checksumAsset.browserDownloadURL)
            try verifyChecksum(dmgURL: dmgURL, checksumURL: checksumURL)
        }

        let mountPoint = try mount(dmgURL)
        defer { unmount(mountPoint) }

        let bundledApp = URL(fileURLWithPath: mountPoint).appendingPathComponent("DropStation.app")
        guard FileManager.default.fileExists(atPath: bundledApp.path) else { throw InstallError.appMissing }
        let stagedApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropStation-update-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: bundledApp, to: stagedApp)

        try scheduleSwapAndRelaunch(newApp: stagedApp)
    }

    private static func download(_ url: URL) async throws -> URL {
        let (data, response) = try await UpdateChecker.makeSession().data(for: UpdateChecker.makeRequest(url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallError.downloadFailed
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropstation-\(UUID().uuidString)-\(url.lastPathComponent)")
        try data.write(to: destination)
        return destination
    }

    static func verifyChecksum(dmgURL: URL, checksumURL: URL) throws {
        let expected = (try? String(contentsOf: checksumURL, encoding: .utf8))?
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased()
        guard let expected, !expected.isEmpty else { throw InstallError.checksumMismatch }
        let actual = SHA256.hash(data: try Data(contentsOf: dmgURL))
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == expected else { throw InstallError.checksumMismatch }
    }

    private static func mount(_ dmgURL: URL) throws -> String {
        let mountPoint = "/tmp/dropstation-mount-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", dmgURL.path, "-nobrowse", "-mountpoint", mountPoint, "-quiet"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.mountFailed }
        return mountPoint
    }

    private static func unmount(_ mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(atPath: mountPoint)
    }

    /// 写入一个等待本进程退出后再替换应用并重启的脚本；脚本启动后由调用方决定是否立即 terminate
    private static func scheduleSwapAndRelaunch(newApp: URL) throws {
        let current = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw InstallError.targetNotWritable
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        /usr/bin/ditto "\(newApp.path)" "\(current.path)"
        /usr/bin/open "\(current.path)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropstation-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
    }
}
