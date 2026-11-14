import AppKit
import SwiftUI

struct MirrorSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var video = AppState.shared.video
    @State private var nameDraft = ""
    @State private var showAdvanced = false
    @FocusState private var nameIsFocused: Bool
    #if !APP_STORE
    @StateObject private var updates = UpdateChecker()
    #endif

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("设置").font(.title2.weight(.semibold))
                    Spacer()
                    Button("完成") { MirrorSettingsWindowController.shared.close() }
                        .keyboardShortcut(.cancelAction)
                }
                settingsSection("连接") {
                    connectionPicker
                    connectionSettings
                        .animation(panelAnimation, value: appState.connectionMode)
                    receiverControls
                }
                settingsSection("画面") {
                    advancedSettings
                }
                settingsSection("辅助功能") {
                    Button { WindowPasteWindowController.shared.show() } label: {
                        Label("窗贴 · 截图与粘贴", systemImage: "camera.viewfinder")
                    }
                    Text("在独立窗口中选择截图目标和快捷键，投屏继续运行。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSection("版本") {
                    versionRow
                    if let error = appState.lastError, appState.status == .failed || appState.status == .missingEngine {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                RepositoryFooter(compact: true)
            }
            .padding(22)
        }
        .background(Color(white: 0.075))
        .preferredColorScheme(.dark)
        .onAppear { nameDraft = appState.receiverName }
        .onChange(of: appState.receiverName) { _, value in
            if nameDraft != value { nameDraft = value }
        }
        .onChange(of: nameIsFocused) { _, focused in
            if !focused { commitName() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == MirrorSettingsWindowController.identifier else { return }
            commitName()
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1))
        }
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.36, dampingFraction: 0.9)
    }
    private var detailTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6))
    }

    private var receiverControls: some View {
        HStack(spacing: 12) {
            if appState.isReceiverActive {
                Button(appState.connectionMode == .usb ? "停止有线投屏" : "停止广播") { appState.stopReceiver() }
            } else {
                Button(appState.connectionMode == .usb ? "开始有线投屏" : "开始广播") {
                    commitName()
                    appState.startReceiver()
                }
                .keyboardShortcut(.defaultAction)
            }
            Button(appState.connectionMode == .usb ? "重新连接" : "重新广播") {
                commitName()
                appState.restart()
            }
            .disabled(appState.connectionMode == .wireless && appState.status == .missingEngine)
        }
    }

    private var connectionPicker: some View {
        Picker("连接方式", selection: $appState.connectionMode) {
            ForEach(ConnectionMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var connectionSettings: some View {
        ZStack(alignment: .topLeading) {
            if appState.connectionMode == .wireless {
                wirelessSettings
                    .transition(detailTransition)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    WiredDeviceControls()
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("播放设备声音", isOn: $appState.wiredAudioEnabled)
                            .foregroundStyle(.white)
                        Text("开启时需要麦克风权限，用于接收数据线传来的设备声音。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = appState.wiredAudioMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                }
                .transition(detailTransition)
            }
        }
    }

    private var wirelessSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("显示名")
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 72, alignment: .leading)
                TextField("镜投", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameIsFocused)
                    .onSubmit { commitName() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("画质与延迟")
                    .foregroundStyle(.white.opacity(0.7))
                Picker("画质与延迟", selection: $appState.quality) {
                    ForEach(StreamQuality.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(appState.quality.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("帧率")
                    .foregroundStyle(.white.opacity(0.7))
                Picker("帧率", selection: $appState.fps) {
                    ForEach(StreamFPS.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("连接时需要配对码", isOn: $appState.requirePin)
                .foregroundStyle(.white)
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(panelAnimation) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("高级设置")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                        .animation(reduceMotion ? nil : panelAnimation, value: showAdvanced)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(SoftButtonStyle())

            if showAdvanced {
                advancedControls
                    .transition(detailTransition)
            }
        }
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("比例设置", isOn: $appState.allowsCustomAspect)
                .foregroundStyle(.white)
            Text(appState.allowsCustomAspect
                 ? "拖动滑块把画面调窄或调宽。窗口仍然只能放大或缩小。"
                 : "窗口只能放大或缩小，投屏比例保持不变。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            if appState.allowsCustomAspect {
                HStack(spacing: 8) {
                    Text("更窄")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Slider(value: $appState.aspectScale, in: 0.6...1.8)
                    Text("更宽")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .transition(detailTransition)
            }
            if video.videoSize.width > 1, video.videoSize.height > 1 {
                Text("设备画面 \(Int(video.videoSize.width.rounded())) × \(Int(video.videoSize.height.rounded()))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Button("重置比例") {
                appState.resetAspectRatio()
            }
        }
        .animation(panelAnimation, value: appState.allowsCustomAspect)
    }

    private var versionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("版本 \(AppVersion.current)")
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                #if !APP_STORE
                Button(updates.phase == .checking ? "正在检查…" : "检查更新") {
                    updates.check()
                }
                .disabled(updates.phase == .checking)
                #endif
            }
            #if !APP_STORE
            switch updates.phase {
            case .idle, .checking:
                EmptyView()
            case .upToDate:
                Text("已是最新版本")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            case .available(let version, let url):
                HStack {
                    Text("发现新版本 \(version)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button("下载") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .failed:
                Text("没有连上，稍后再试")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            #endif
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.receiverName = trimmed.isEmpty ? "镜投" : trimmed
        nameDraft = appState.receiverName
    }
}
