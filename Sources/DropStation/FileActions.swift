import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 三个内置图片处理动作的预设参数，UserDefaults 持久化，由设置窗口调整。
enum ActionSettings {
    static func register() {
        UserDefaults.standard.register(defaults: [
            "action.compressQuality": 80,
            "action.resizeMaxWidth": 1000,
            "action.resizeMaxHeight": 1000,
            "action.convertFormat": "JPEG",
            "action.convertQuality": 100,
        ])
    }

    static var compressQuality: Int {
        get { UserDefaults.standard.integer(forKey: "action.compressQuality") }
        set { UserDefaults.standard.set(newValue, forKey: "action.compressQuality") }
    }

    static var resizeMaxWidth: Int {
        get { UserDefaults.standard.integer(forKey: "action.resizeMaxWidth") }
        set { UserDefaults.standard.set(newValue, forKey: "action.resizeMaxWidth") }
    }

    static var resizeMaxHeight: Int {
        get { UserDefaults.standard.integer(forKey: "action.resizeMaxHeight") }
        set { UserDefaults.standard.set(newValue, forKey: "action.resizeMaxHeight") }
    }

    static var convertFormat: String {
        get { UserDefaults.standard.string(forKey: "action.convertFormat") ?? "JPEG" }
        set { UserDefaults.standard.set(newValue, forKey: "action.convertFormat") }
    }

    static var convertQuality: Int {
        get { UserDefaults.standard.integer(forKey: "action.convertQuality") }
        set { UserDefaults.standard.set(newValue, forKey: "action.convertQuality") }
    }
}

/// 纯逻辑的图片处理引擎，无 UI 依赖，可在任意线程调用。
enum FileActions {

    enum ActionError: Error {
        case unreadable
        case writeFailed
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .image)
    }

    /// 压缩为 JPEG（alpha 压白底），输出 `原名-压缩.jpg`
    static func compressJPEG(at url: URL, qualityPercent: Int) throws -> URL {
        try reencode(at: url,
                     outputType: .jpeg,
                     quality: CGFloat(qualityPercent) / 100,
                     maxPixelSize: nil,
                     flattenToWhite: true,
                     suffix: "压缩",
                     newExtension: "jpg")
    }

    /// 等比缩放到不超过 maxWidth×maxHeight（只缩小不放大），保留原格式，输出 `原名-缩放.原扩展名`
    static func resize(at url: URL, maxWidth: Int, maxHeight: Int) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(source),
              let utType = UTType(typeIdentifier as String) else { throw ActionError.unreadable }
        return try reencode(at: url,
                            outputType: utType,
                            quality: nil,
                            maxPixelSize: CGSize(width: maxWidth, height: maxHeight),
                            flattenToWhite: false,
                            suffix: "缩放",
                            newExtension: nil)
    }

    /// 转换格式，输出 `原名.jpg` / `原名.png`
    static func convert(at url: URL, toJPEG: Bool, qualityPercent: Int) throws -> URL {
        try reencode(at: url,
                     outputType: toJPEG ? .jpeg : .png,
                     quality: toJPEG ? CGFloat(qualityPercent) / 100 : nil,
                     maxPixelSize: nil,
                     flattenToWhite: toJPEG,
                     suffix: "",
                     newExtension: toJPEG ? "jpg" : "png")
    }

    private static func reencode(at url: URL,
                                 outputType: UTType,
                                 quality: CGFloat?,
                                 maxPixelSize: CGSize?,
                                 flattenToWhite: Bool,
                                 suffix: String,
                                 newExtension: String?) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ActionError.unreadable
        }
        if let maxPixelSize {
            image = scaled(image, maxPixelSize: maxPixelSize)
        }
        if flattenToWhite {
            image = flattened(image)
        }

        let ext = newExtension ?? url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let name = suffix.isEmpty ? "\(stem).\(ext)" : "\(stem)-\(suffix).\(ext)"
        let destURL = uniqueURL(url.deletingLastPathComponent().appendingPathComponent(name))

        guard let destination = CGImageDestinationCreateWithURL(destURL as CFURL, outputType.identifier as CFString, 1, nil) else {
            throw ActionError.writeFailed
        }
        var options: [CFString: Any] = [:]
        if let quality {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destURL)
            throw ActionError.writeFailed
        }
        return destURL
    }

    private static func scaled(_ image: CGImage, maxPixelSize: CGSize) -> CGImage {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let factor = min(maxPixelSize.width / width, maxPixelSize.height / height)
        guard factor < 1 else { return image }
        let targetWidth = max(1, Int((width * factor).rounded(.down)))
        let targetHeight = max(1, Int((height * factor).rounded(.down)))
        guard let context = CGContext(data: nil,
                                      width: targetWidth,
                                      height: targetHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    private static func flattened(_ image: CGImage) -> CGImage {
        guard let context = CGContext(data: nil,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// 输出文件已存在时追加 -2、-3…，避免覆盖用户已有文件
    private static func uniqueURL(_ base: URL) -> URL {
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let directory = base.deletingLastPathComponent()
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        for index in 2...99 {
            let candidate = directory.appendingPathComponent("\(stem)-\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return base
    }

    /// 隐藏自测入口：`DropStation --selftest <图片路径>`，验证三个动作并打印结果
    static func runSelfTest(imagePath: String) -> Never {
        let url = URL(fileURLWithPath: imagePath)
        print("selftest input: \(url.path), isImage=\(isImage(url))")
        do {
            let compressed = try compressJPEG(at: url, qualityPercent: ActionSettings.compressQuality)
            print("compress -> \(compressed.lastPathComponent) (\(byteSize(compressed)) bytes)")
            let resized = try resize(at: url, maxWidth: ActionSettings.resizeMaxWidth, maxHeight: ActionSettings.resizeMaxHeight)
            print("resize   -> \(resized.lastPathComponent) (\(dimensions(resized)))")
            let converted = try convert(at: url, toJPEG: ActionSettings.convertFormat == "JPEG", qualityPercent: ActionSettings.convertQuality)
            print("convert  -> \(converted.lastPathComponent) (\(byteSize(converted)) bytes)")
        } catch {
            print("selftest FAILED: \(error)")
        }
        exit(0)
    }

    private static func byteSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private static func dimensions(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return "unknown" }
        return "\(width)x\(height)"
    }
}
