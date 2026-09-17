import Foundation

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

enum UpdateCheckResult: Sendable {
    case updateAvailable(GitHubRelease, version: String)
    case upToDate
    case failed(String)
}

/// 仅允许 https 与白名单主机的重定向，拒绝协议降级、IP 字面量与未知主机。
final class SafeRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private static let allowedHosts: Set<String> = [
        "api.github.com",
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "github-cloud.s3.amazonaws.com",
    ]

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url,
              url.scheme == "https",
              let host = url.host?.lowercased(),
              Self.isAllowed(host: host) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    static func isAllowed(host: String) -> Bool {
        // GitHub 资产域名只会是白名单或其 githubusercontent.com 子域，IP 字面量一律拒绝
        if host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("169.254.")
            || host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("::1") || host.contains(":") { return false }
        return allowedHosts.contains(host) || host.hasSuffix(".githubusercontent.com")
    }
}

enum UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/yiyabo/DropStation/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "updater.skippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "updater.skippedVersion") }
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let remoteParts = parts(remote), localParts = parts(local)
        for index in 0..<max(remoteParts.count, localParts.count) {
            let remoteValue = index < remoteParts.count ? remoteParts[index] : 0
            let localValue = index < localParts.count ? localParts[index] : 0
            if remoteValue != localValue { return remoteValue > localValue }
        }
        return false
    }

    static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral, delegate: SafeRedirectDelegate(), delegateQueue: nil)
    }

    static func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DropStation/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        return request
    }

    static func check() async -> UpdateCheckResult {
        do {
            let (data, response) = try await makeSession().data(for: makeRequest(latestReleaseURL))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("GitHub 返回了异常状态")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName
            guard isVersion(remoteVersion, newerThan: currentVersion) else { return .upToDate }
            return .updateAvailable(release, version: remoteVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
