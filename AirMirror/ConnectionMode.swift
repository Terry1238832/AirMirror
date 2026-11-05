import Foundation

enum ConnectionMode: String, CaseIterable, Identifiable {
    case wireless
    case usb

    var id: String { rawValue }
    var title: String { self == .wireless ? "无线投屏" : "USB 有线" }
    var symbol: String { self == .wireless ? "airplayvideo" : "cable.connector" }
}
