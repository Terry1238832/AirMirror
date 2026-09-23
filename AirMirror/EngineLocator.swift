import Foundation

enum EngineLocator {
    static func find() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "uxplay") {
            candidates.append(bundled)
        }
        let bundle = Bundle.main.bundleURL
        candidates.append(bundle.appendingPathComponent("Contents/Helpers/uxplay"))
        candidates.append(bundle.appendingPathComponent("Contents/MacOS/uxplay"))

        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            home.appendingPathComponent("Library/Application Support/镜投/uxplay"),
            URL(fileURLWithPath: "/opt/homebrew/bin/uxplay"),
            URL(fileURLWithPath: "/usr/local/bin/uxplay")
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for folder in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(folder)).appendingPathComponent("uxplay"))
            }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static var supportDirectory: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/镜投", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
