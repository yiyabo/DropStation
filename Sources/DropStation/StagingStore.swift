import Foundation

struct StagedItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var relativePath: String
    var displayName: String
    let createdAt: Date

    var stagedURL: URL { StagingStore.root.appendingPathComponent(relativePath) }
}

struct StageFailure: Sendable {
    let sourceURL: URL
    let message: String
}

struct StageBatch: Sendable {
    let items: [StagedItem]
    let failures: [StageFailure]
}

enum CloseRetention: String, CaseIterable {
    case discardImmediately
    case retainForThreeDays

    var title: String {
        switch self {
        case .discardImmediately: "立即删除暂存副本"
        case .retainForThreeDays: "保留 3 天"
        }
    }
}

enum StationSettings {
    static func register() {
        UserDefaults.standard.register(defaults: ["station.closeRetention": CloseRetention.discardImmediately.rawValue])
    }

    static var closeRetention: CloseRetention {
        get { CloseRetention(rawValue: UserDefaults.standard.string(forKey: "station.closeRetention") ?? "") ?? .discardImmediately }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "station.closeRetention") }
    }
}

/// 应用私有的文件副本与 manifest。外部源文件从不在这里被删除或移动。
@MainActor
final class StagingStore {
    nonisolated static func rootDirectory(override: URL? = nil) -> URL {
        override ?? root
    }

    nonisolated static let root: URL = {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("DropStation/Staging", isDirectory: true)
    }()

    private static let manifestName = "manifest.json"
    private let fileManager = FileManager.default
    private(set) var items: [StagedItem] = []

    func prepareForLaunch() throws -> [StagedItem] {
        try fileManager.createDirectory(at: Self.root, withIntermediateDirectories: true)
        if StationSettings.closeRetention == .retainForThreeDays {
            items = try loadManifest().filter { item in
                item.createdAt >= Date().addingTimeInterval(-3 * 24 * 60 * 60)
                    && fileManager.fileExists(atPath: item.stagedURL.path)
            }
        } else {
            items = []
        }
        removeUnreferencedFiles()
        try saveManifest()
        return items
    }

    func stage(_ sourceURLs: [URL]) async -> StageBatch {
        let root = Self.root
        let batch = await Task.detached(priority: .userInitiated) {
            var successes: [StagedItem] = []
            var failures: [StageFailure] = []
            for source in sourceURLs {
                do {
                    successes.append(try Self.copy(source: source, to: root))
                } catch {
                    failures.append(StageFailure(sourceURL: source, message: error.localizedDescription))
                }
            }
            return StageBatch(items: successes, failures: failures)
        }.value

        items.append(contentsOf: batch.items)
        do {
            try saveManifest()
            return batch
        } catch {
            batch.items.forEach { try? fileManager.removeItem(at: $0.stagedURL) }
            let ids = Set(batch.items.map(\.id))
            items.removeAll { ids.contains($0.id) }
            return StageBatch(
                items: [],
                failures: batch.failures + batch.items.map {
                    StageFailure(sourceURL: $0.stagedURL, message: error.localizedDescription)
                }
            )
        }
    }

    func remove(_ item: StagedItem) {
        items.removeAll { $0.id == item.id }
        try? fileManager.removeItem(at: item.stagedURL)
        try? saveManifest()
    }

    func removeAll(_ entries: [StagedItem]) {
        let ids = Set(entries.map(\.id))
        entries.forEach { try? fileManager.removeItem(at: $0.stagedURL) }
        items.removeAll { ids.contains($0.id) }
        try? saveManifest()
    }

    func replace(_ item: StagedItem, with outputURL: URL) -> StagedItem? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        let oldURL = item.stagedURL
        guard outputURL.standardizedFileURL != oldURL.standardizedFileURL,
              outputURL.deletingLastPathComponent().standardizedFileURL == Self.root.standardizedFileURL else { return nil }
        items[index].relativePath = outputURL.lastPathComponent
        items[index].displayName = stripSuffix(from: outputURL.lastPathComponent)
        try? fileManager.removeItem(at: oldURL)
        try? saveManifest()
        return items[index]
    }

    func discardAll() {
        removeAll(items)
    }

    func promiseReceivingDirectory() throws -> URL {
        let directory = Self.root.appendingPathComponent(".incoming-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func removeIncomingDirectory(_ directory: URL) {
        try? fileManager.removeItem(at: directory)
    }

    private func loadManifest() throws -> [StagedItem] {
        let manifest = Self.root.appendingPathComponent(Self.manifestName)
        guard fileManager.fileExists(atPath: manifest.path) else { return [] }
        do {
            return try JSONDecoder().decode([StagedItem].self, from: Data(contentsOf: manifest))
        } catch {
            try? fileManager.removeItem(at: manifest)
            return []
        }
    }

    private func saveManifest() throws {
        let manifest = Self.root.appendingPathComponent(Self.manifestName)
        try JSONEncoder().encode(items).write(to: manifest, options: .atomic)
    }

    private func removeUnreferencedFiles() {
        let allowed = Set(items.map(\.relativePath)).union([Self.manifestName])
        guard let children = try? fileManager.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil) else { return }
        for child in children where !allowed.contains(child.lastPathComponent) {
            try? fileManager.removeItem(at: child)
        }
    }

    private nonisolated static func uniqueName(_ originalName: String, in root: URL) -> String {
        let pathExtension = URL(fileURLWithPath: originalName).pathExtension
        let stem = URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let name: String
            if index == 1 {
                name = originalName
            } else if pathExtension.isEmpty {
                name = "\(stem)-\(index)"
            } else {
                name = "\(stem)-\(index).\(pathExtension)"
            }
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) { return name }
        }
        return "\(UUID().uuidString)-\(originalName)"
    }

    private func stripSuffix(from name: String) -> String {
        name.replacingOccurrences(of: #"\s-\d+(?=\.)"#, with: "", options: .regularExpression)
    }

    private nonisolated static func copy(source: URL, to root: URL) throws -> StagedItem {
        let isIncoming = source.deletingLastPathComponent().lastPathComponent.hasPrefix(".incoming-")
        let hasSecurityScope = !isIncoming && source.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { source.stopAccessingSecurityScopedResource() } }

        let values = try source.resourceValues(forKeys: [.isReadableKey, .isSymbolicLinkKey, .isDirectoryKey, .nameKey])
        guard values.isReadable == true else { throw CocoaError(.fileReadNoPermission) }
        guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        if values.isDirectory != true {
            let probe = try FileHandle(forReadingFrom: source)
            try probe.close()
        }

        let id = UUID()
        let originalName = values.name ?? source.lastPathComponent
        let targetName = uniqueName(originalName, in: root)
        let target = root.appendingPathComponent(targetName)

        if isIncoming {
            do {
                try FileManager.default.moveItem(at: source, to: target)
                try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            } catch {
                try? FileManager.default.removeItem(at: target)
                throw error
            }
        } else {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedSource in
                do { try FileManager.default.copyItem(at: coordinatedSource, to: target) }
                catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError {
                try? FileManager.default.removeItem(at: target)
                throw copyError
            }
        }
        return StagedItem(id: id, relativePath: targetName, displayName: originalName, createdAt: Date())
    }
}
