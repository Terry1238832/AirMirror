import AppKit
import SwiftUI

struct WiredDeviceControls: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        wiredDeviceControls
    }

    private var wiredDeviceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.wiredDevices.isEmpty {
                Picker("设备", selection: $appState.selectedWiredDeviceID) {
                    Text("自动选择").tag(String?.none)
                    if let previous = appState.selectedWiredDeviceID,
                       !appState.wiredDevices.contains(where: { $0.id == previous }) {
                        Text("上次选择的设备（未连接）").tag(Optional(previous))
                    }
                    ForEach(appState.wiredDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
            } else {
                Label("尚未检测到可用设备", systemImage: "ipad")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(spacing: 12) {
                if appState.status == .idle {
                    Button("开始有线投屏") { appState.startReceiver() }
                } else {
                    Button("重新检测设备") { appState.refreshWiredDevices() }
                }
                if appState.wiredPermissionDenied {
                    Button("打开相机权限设置") { WiredDevicePermissions.openCameraSettings() }
                }
            }

            if appState.wiredPermissionDenied {
                Text("在「隐私与安全性 → 相机」中允许镜投，然后重新检测设备。系统可能要求重新打开应用。")
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
