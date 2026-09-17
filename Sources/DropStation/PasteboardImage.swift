import AppKit

/// 从拖拽粘贴板直接提取位图数据：覆盖微信图片查看器这类
/// 不提供可读文件路径、也不走 file promise 的拖拽来源。
enum PasteboardImage {

    private static let preferredTypes: [(NSPasteboard.PasteboardType, String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
        (.tiff, "tiff"),
        (NSPasteboard.PasteboardType("public.webp"), "webp"),
        (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
    ]

    static func payload(from pasteboard: NSPasteboard) -> (data: Data, fileExtension: String)? {
        for (type, ext) in preferredTypes {
            if let data = pasteboard.data(forType: type) {
                return (data, ext)
            }
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    static func hasImageData(_ pasteboard: NSPasteboard) -> Bool {
        let types = Set(pasteboard.types ?? [])
        return preferredTypes.contains { types.contains($0.0) }
    }
}
