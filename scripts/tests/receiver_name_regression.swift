import Foundation

@main struct ReceiverNameRegression {
    static func main() {
        let suite = "AirMirror.ReceiverNameRegression." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func reset() { defaults.removePersistentDomain(forName: suite) }

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

        precondition(ReceiverNamePreference.save("  ", deviceName: "我的 Mac", to: defaults) == "我的 Mac")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(defaults.object(forKey: "receiverNameOverride") == nil)
        precondition(ReceiverNamePreference.save(" 我的 Mac ", deviceName: "我的 Mac", to: defaults) == "我的 Mac")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(ReceiverNamePreference.save("工作室", deviceName: "我的 Mac", to: defaults) == "工作室")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == "工作室")

        reset()
        defaults.set("\n ", forKey: "receiverNameOverride")
        precondition(ReceiverNamePreference.loadOverride(from: defaults) == nil)
        precondition(ReceiverNamePreference.save("", deviceName: " ", to: defaults) == "Mac")
        precondition(!ReceiverNamePreference.deviceName.isEmpty)
        print("PASS: automatic device naming, legacy migration, custom-name preservation and reset")
    }
}
