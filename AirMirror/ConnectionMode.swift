import Foundation

enum ConnectionMode: String, CaseIterable, Identifiable {
    case wireless
    case usb

    var id: String { rawValue }
    var title: String { self == .wireless ? L10n.tr("无线投屏") : L10n.tr("USB 有线") }
    var symbol: String { self == .wireless ? "airplayvideo" : "cable.connector" }
}
