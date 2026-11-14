import AppKit
import SwiftUI

struct WiredDeviceControls: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        wiredDeviceControls
    }

    private var wiredDeviceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.wiredDevices.isEmpty {
                Picker(L10n.tr("设备"), selection: $appState.selectedWiredDeviceID) {
                    Text(L10n.tr("自动选择")).tag(String?.none)
                    if let previous = appState.selectedWiredDeviceID,
                       !appState.wiredDevices.contains(where: { $0.id == previous }) {
                        Text(L10n.tr("上次选择的设备（未连接）")).tag(Optional(previous))
                    }
                    ForEach(appState.wiredDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                Label(L10n.tr("尚未检测到可用设备"), systemImage: "ipad")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(spacing: 12) {
                if appState.status == .idle {
                    Button(L10n.tr("开始有线投屏")) { appState.startReceiver() }
                } else {
                    Button(L10n.tr("重新检测设备")) { appState.refreshWiredDevices() }
                }
                if appState.wiredPermissionDenied {
                    Button(L10n.tr("打开相机权限设置")) { WiredDevicePermissions.openCameraSettings() }
                }
            }

            if appState.wiredPermissionDenied {
                Text(L10n.tr("在「隐私与安全性 → 相机」中允许镜投，然后重新检测设备。系统可能要求重新打开应用。"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

enum WiredDevicePermissions {
    static func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}
