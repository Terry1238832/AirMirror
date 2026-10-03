import AppKit
import Foundation

enum AppVersion {
    static var current: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let version, !version.isEmpty {
            return version
        }
        return "1.0.2"
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var phase: Phase = .idle

    func check() {
        guard phase != .checking else { return }
        phase = .checking
        Task { await fetch() }
    }

    private func fetch() async {
        guard let endpoint = URL(string: "https://api.github.com/repos/Terry1238832/AirMirror/releases/latest") else {
            phase = .failed
            return
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AirMirror", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                phase = .failed
                return
            }
            let release = try JSONDecoder().decode(LatestRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.isNewer(latest, than: AppVersion.current) {
                let page = release.htmlURL ?? URL(string: "https://github.com/Terry1238832/AirMirror/releases/latest")!
                phase = .available(version: latest, url: page)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed
        }
    }

    private static func isNewer(_ latest: String, than current: String) -> Bool {
        let left = latest.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let newer = index < left.count ? left[index] : 0
            let installed = index < right.count ? right[index] : 0
            if newer != installed { return newer > installed }
        }
        return false
    }
}

private struct LatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
