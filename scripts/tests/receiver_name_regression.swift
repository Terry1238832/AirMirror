import Foundation

@main struct ReceiverNameRegression {
    static func main() {
        let suite = "AirMirror.ReceiverNameRegression." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func reset() { defaults.removePersistentDomain(forName: suite) }
        let automatic = ReceiverNamePreference.defaultName(deviceName: "我的 Mac", preferredLanguages: ["zh-Hans", "en"])
        precondition(automatic == "镜投 - 我的 Mac")
        precondition(ReceiverNamePreference.defaultName(deviceName: "My Mac", preferredLanguages: ["en-CA", "zh-Hans"]) == "AirMirror - My Mac")
        precondition(ReceiverNamePreference.defaultName(deviceName: " 我的 Mac ", preferredLanguages: ["zh-Hant"]) == "鏡投 - 我的 Mac")
        precondition(ReceiverNamePreference.defaultName(deviceName: "  ", preferredLanguages: []) == "AirMirror - Mac")
        precondition(AppLanguage.resolve(preferredLanguages: ["zh_TW"]) == .traditionalChinese)
        precondition(AppLanguage.resolve(preferredLanguages: ["zh-HK"]) == .traditionalChinese)
        precondition(AppLanguage.resolve(preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
        precondition(AppLanguage.resolve(preferredLanguages: ["pt-PT"]) == .portuguese)
        precondition(AppLanguage.resolve(preferredLanguages: ["nl-NL", "fr-CA"]) == .french)
        precondition(AppLanguage.resolve(preferredLanguages: ["xx"]) == .english)
        precondition(AppLanguage.arabic.isRightToLeft && !AppLanguage.hindi.isRightToLeft)

        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        defaults.set("镜投", forKey: "receiverName")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(defaults.object(forKey: "receiverName") == nil)

        defaults.set("  自定义接收端 \n", forKey: "receiverName")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == "自定义接收端")
        precondition(defaults.string(forKey: "receiverNameOverride") == "自定义接收端")
        precondition(defaults.object(forKey: "receiverName") == nil)

        defaults.set("旧名称", forKey: "receiverName")
        defaults.set("镜投", forKey: "receiverNameOverride")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == "镜投",
                     "An explicitly customized brand name in the new schema must survive")
        precondition(defaults.object(forKey: "receiverName") == nil)

        precondition(ReceiverNamePreference.save("  ", defaultName: automatic, to: defaults) == automatic)
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(defaults.object(forKey: "receiverNameOverride") == nil)
        precondition(ReceiverNamePreference.save(" \(automatic) ", defaultName: automatic, to: defaults) == automatic)
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(ReceiverNamePreference.save("工作室", defaultName: automatic, to: defaults) == "工作室")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == "工作室")

        reset()
        defaults.set("\n ", forKey: "receiverNameOverride")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(ReceiverNamePreference.save("", defaultName: " ", to: defaults) == ReceiverNamePreference.defaultName)
        precondition(!ReceiverNamePreference.deviceName.isEmpty)
        print("PASS: Chinese/English branded naming, legacy migration, custom-name preservation and reset")
    }
}
