import Foundation
import SystemConfiguration

enum ReceiverNamePreference {
    private static let overrideKey = "receiverNameOverride"
    private static let legacyKey = "receiverName"

    static var deviceName: String {
        clean(SCDynamicStoreCopyComputerName(nil, nil) as String?)
            ?? clean(Host.current().localizedName)
            ?? "Mac"
    }

    static var defaultName: String { defaultName(deviceName: deviceName, preferredLanguages: [L10n.language.rawValue]) }

    static func defaultName(deviceName: String, preferredLanguages: [String]) -> String {
        "\(AppBrand.name(for: preferredLanguages)) - \(clean(deviceName) ?? "Mac")"
    }

    /// Migrate the former fixed default without discarding an existing custom name.
    static func loadOverride(from defaults: UserDefaults) -> String? {
        defer { defaults.removeObject(forKey: legacyKey) }
        if defaults.object(forKey: overrideKey) != nil {
            let name = clean(defaults.string(forKey: overrideKey))
            if name == nil { defaults.removeObject(forKey: overrideKey) }
            return name
        }
        guard let name = clean(defaults.string(forKey: legacyKey)), name != "镜投" else { return nil }
        defaults.set(name, forKey: overrideKey)
        return name
    }

    @discardableResult
    static func save(_ proposed: String, defaultName: String, to defaults: UserDefaults) -> String {
        let fallback = clean(defaultName) ?? Self.defaultName
        defaults.removeObject(forKey: legacyKey)
        guard let name = clean(proposed), name != fallback else {
            // Keep automatic naming automatic after the Mac is renamed or the app reopens.
            defaults.removeObject(forKey: overrideKey)
            return fallback
        }
        defaults.set(name, forKey: overrideKey)
        return name
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
