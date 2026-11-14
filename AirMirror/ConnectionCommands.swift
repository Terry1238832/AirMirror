import SwiftUI

struct ConnectionCommands: Commands {
    @ObservedObject private var language = LanguagePreferences.shared
    @ObservedObject private var appState = AppState.shared

    var body: some Commands {
        CommandMenu(L10n.tr("连接")) {
            Picker(L10n.tr("连接方式"), selection: $appState.connectionMode) {
                ForEach(ConnectionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()
            if appState.connectionMode == .wireless {
                Picker(L10n.tr("画质与延迟"), selection: $appState.quality) {
                    ForEach(StreamQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                Picker(L10n.tr("帧率"), selection: $appState.fps) {
                    ForEach(StreamFPS.allCases) { fps in
                        Text(fps.title).tag(fps)
                    }
                }
                Toggle(L10n.tr("连接时需要配对码"), isOn: $appState.requirePin)
            } else {
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
                Button(L10n.tr("重新检测设备")) { appState.refreshWiredDevices() }
                if appState.wiredPermissionDenied {
                    Button(L10n.tr("打开相机权限设置")) { WiredDevicePermissions.openCameraSettings() }
                }
                Toggle(L10n.tr("播放设备声音"), isOn: $appState.wiredAudioEnabled)
                    .help(L10n.tr("需要麦克风权限，用于接收数据线传来的设备声音。"))
            }

            Divider()
            if appState.isReceiverActive {
                Button(appState.connectionMode == .usb ? L10n.tr("停止有线投屏") : L10n.tr("停止广播")) {
                    appState.stopReceiver()
                }
            } else {
                Button(appState.connectionMode == .usb ? L10n.tr("开始有线投屏") : L10n.tr("开始广播")) {
                    appState.startReceiver()
                }
            }
            Button(appState.connectionMode == .usb ? L10n.tr("重新连接") : L10n.tr("重新广播")) {
                appState.restart()
            }
            .disabled(appState.connectionMode == .wireless && appState.status == .missingEngine)
        }
    }
}
