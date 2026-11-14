import Foundation

enum StreamQuality: String, CaseIterable, Identifiable {
    case fluent
    case balanced
    case sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fluent: return L10n.tr("流畅")
        case .balanced: return L10n.tr("平衡")
        case .sharp: return L10n.tr("高清")
        }
    }

    var subtitle: String {
        switch self {
        case .fluent: return L10n.tr("720p，延迟最低，适合跟手操作")
        case .balanced: return L10n.tr("1080p，画质和延迟折中")
        case .sharp: return L10n.tr("最高画质，按设备能力协商分辨率")
        }
    }

    /// Height is the size AirPlay clients actually honor.
    var sizeArgument: String {
        switch self {
        case .fluent: return "1280x720@60"
        case .balanced: return "1920x1080@60"
        case .sharp: return "3840x2160@60"
        }
    }
}

enum StreamFPS: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) fps"
    }
}
