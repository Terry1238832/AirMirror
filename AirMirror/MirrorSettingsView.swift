import AppKit
import SwiftUI

struct MirrorSettingsView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var video = AppState.shared.video
    @State private var nameDraft = ""
    @FocusState private var nameIsFocused: Bool
    #if !APP_STORE
    @StateObject private var updates = UpdateChecker()
    #endif

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L10n.tr("设置")).font(.title2.weight(.semibold))
                    Spacer()
                    Button(L10n.tr("完成")) { MirrorSettingsWindowController.shared.close() }
                        .keyboardShortcut(.cancelAction)
                }
                settingsSection(L10n.tr("通用")) {
                    LanguagePicker()
                    Text(L10n.tr("切换语言后立即生效。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                settingsSection(L10n.tr("连接")) {
                    connectionPicker
                    connectionSettings
                        .animation(panelAnimation, value: appState.connectionMode)
                    receiverControls
                }
                settingsSection(L10n.tr("画面")) {
                    pictureControls
                }
                settingsSection(L10n.tr("辅助功能")) {
                    Button { WindowPasteWindowController.shared.show() } label: {
                        Label(L10n.tr("窗贴 · 截图与粘贴"), systemImage: "camera.viewfinder")
                    }
                    Text(L10n.tr("在独立窗口中选择截图目标和快捷键，投屏继续运行。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSection(L10n.tr("版本")) {
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
        .appLanguageEnvironment()
        .onChange(of: language.selection) { _, _ in
            MirrorSettingsWindowController.shared.window?.title = L10n.tr("设置 · 镜投")
        }
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
                Button(appState.connectionMode == .usb ? L10n.tr("停止有线投屏") : L10n.tr("停止广播")) { appState.stopReceiver() }
            } else {
                Button(appState.connectionMode == .usb ? L10n.tr("开始有线投屏") : L10n.tr("开始广播")) {
                    commitName()
                    appState.startReceiver()
                }
                .keyboardShortcut(.defaultAction)
            }
            Button(appState.connectionMode == .usb ? L10n.tr("重新连接") : L10n.tr("重新广播")) {
                commitName()
                appState.restart()
            }
            .disabled(appState.connectionMode == .wireless && appState.status == .missingEngine)
        }
    }

    private var connectionPicker: some View {
        Picker(L10n.tr("连接方式"), selection: $appState.connectionMode) {
            ForEach(ConnectionMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .id(language.selection)
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
                        Toggle(L10n.tr("播放设备声音"), isOn: $appState.wiredAudioEnabled)
                            .foregroundStyle(.white)
                        Text(L10n.tr("开启时需要麦克风权限，用于接收数据线传来的设备声音。"))
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
                Text(L10n.tr("显示名"))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 72, alignment: .leading)
                TextField(AppState.defaultReceiverName, text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameIsFocused)
                    .onSubmit { commitName() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("画质与延迟"))
                    .foregroundStyle(.white.opacity(0.7))
                Picker(L10n.tr("画质与延迟"), selection: $appState.quality) {
                    ForEach(StreamQuality.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(language.selection)
                Text(appState.quality.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("帧率"))
                    .foregroundStyle(.white.opacity(0.7))
                Picker(L10n.tr("帧率"), selection: $appState.fps) {
                    ForEach(StreamFPS.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(language.selection)
            }

            Toggle(L10n.tr("连接时需要配对码"), isOn: $appState.requirePin)
                .foregroundStyle(.white)
        }
    }

    private var pictureControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.tr("比例设置"), isOn: $appState.allowsCustomAspect)
                .foregroundStyle(.white)
            Text(appState.allowsCustomAspect
                 ? L10n.tr("拖动滑块把画面调窄或调宽。窗口仍然只能放大或缩小。")
                 : L10n.tr("窗口只能放大或缩小，投屏比例保持不变。"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            if appState.allowsCustomAspect {
                HStack(spacing: 8) {
                    Text(L10n.tr("更窄"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Slider(value: $appState.aspectScale, in: 0.6...1.8)
                    Text(L10n.tr("更宽"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .transition(detailTransition)
            }
            if video.videoSize.width > 1, video.videoSize.height > 1 {
                Text(L10n.tr("设备画面 %1$@ × %2$@", String(describing: Int(video.videoSize.width.rounded())), String(describing: Int(video.videoSize.height.rounded()))))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Button(L10n.tr("重置比例")) {
                appState.resetAspectRatio()
            }
        }
        .animation(panelAnimation, value: appState.allowsCustomAspect)
    }

    private var versionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("版本 %1$@", String(describing: AppVersion.current)))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                #if !APP_STORE
                Button(updates.phase == .checking ? L10n.tr("正在检查…") : L10n.tr("检查更新")) {
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
                Text(L10n.tr("已是最新版本"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            case .available(let version, let url):
                HStack {
                    Text(L10n.tr("发现新版本 %1$@", String(describing: version)))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Button(L10n.tr("下载")) {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .failed:
                Text(L10n.tr("没有连上，稍后再试"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            #endif
        }
    }

    private func commitName() {
        appState.setReceiverName(nameDraft)
        nameDraft = appState.receiverName
    }
}
