import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var discovery: DiscoveryMonitor
    @ObservedObject private var video: VideoBridge
    @State private var nameDraft: String = ""
    @State private var showSettings = false
    @State private var showAdvanced = false
    @StateObject private var updates = UpdateChecker()

    init() {
        _discovery = ObservedObject(wrappedValue: AppState.shared.discovery)
        _video = ObservedObject(wrappedValue: AppState.shared.video)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoCanvas(bridge: video)
                .opacity(video.hasVideo ? 1 : 0)
                .animation(fadeAnimation, value: video.hasVideo)

            ZStack {
                if !video.hasVideo {
                    waitingLayout
                        .transition(.opacity)
                } else {
                    streamingOverlay
                        .transition(.opacity)
                }
            }
            .animation(fadeAnimation, value: video.hasVideo)
            .allowsHitTesting(!showSettings)
            .accessibilityHidden(showSettings)

            if showSettings {
                settingsBackdrop
                    .transition(.opacity)
                    .zIndex(1)
                settingsPanel
                    .transition(panelTransition)
                    .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .background(
            WindowAspectLock(
                streaming: video.hasVideo,
                videoSize: video.videoSize,
                allowsCustomAspect: appState.allowsCustomAspect,
                aspectScale: appState.aspectScale,
                resetToken: appState.aspectResetToken,
                reduceMotion: reduceMotion,
                bridge: video
            )
        )
        .onAppear {
            nameDraft = appState.receiverName
        }
        .onChange(of: appState.receiverName) { _, newValue in
            if nameDraft != newValue {
                nameDraft = newValue
            }
        }
        .onChange(of: video.hasVideo) { _, streaming in
            if streaming {
                withAnimation(panelAnimation) {
                    showSettings = false
                }
            }
        }
        .onExitCommand {
            if showSettings { dismissSettings() }
        }
    }

    private var fadeAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.1 : 0.2) }
    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.36, dampingFraction: 0.9)
    }
    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.985, anchor: .top))
    }
    private var detailTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6))
    }

    private func presentSettings() {
        withAnimation(panelAnimation) { showSettings = true }
    }

    private func dismissSettings() {
        commitName()
        withAnimation(panelAnimation) { showSettings = false }
    }

    private var waitingLayout: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 36)
            ScrollView(.vertical, showsIndicators: false) {
                waiting
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
            Button {
                presentSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(SoftButtonStyle())
            .padding(.bottom, 22)
        }
    }

    private var streamingOverlay: some View {
        VStack {
            HStack(spacing: 10) {
                if let client = appState.connectedClient {
                    Text(client)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                Spacer()
                Button {
                    presentSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(SoftButtonStyle(hoverScale: 1.045))
            }
            .padding(.horizontal, 14)
            .padding(.top, 40)
            Spacer()
        }
    }

    private var settingsBackdrop: some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { dismissSettings() }
    }

    private var settingsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            settingsCard
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { }
                .frame(maxWidth: 520)
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
        }
        .onTapGesture { dismissSettings() }
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            Image(systemName: appState.connectionMode.symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .animation(fadeAnimation, value: appState.connectionMode)

            Text("等待投屏")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            connectionPicker
                .frame(maxWidth: 320)

            Text(statusLine)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
                .contentTransition(.opacity)
                .animation(fadeAnimation, value: statusLine)

            if appState.connectionMode == .wireless, let pin = appState.pinCode {
                Text("配对码 \(pin)")
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .transition(detailTransition)
            }

            instructionCard
                .padding(.top, 6)
        }
        .padding(.horizontal, 36)
        .animation(fadeAnimation, value: appState.pinCode)
    }

    private var statusLine: String {
        if appState.connectionMode == .wireless, discovery.isVisibleOnLan,
           appState.status == .advertising {
            return "已可被局域网内的 iPhone / iPad 搜索到"
        }
        return appState.statusText
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

    private var instructionCard: some View {
        ZStack(alignment: .topLeading) {
            if appState.connectionMode == .wireless {
                wirelessInstructions
                    .transition(detailTransition)
            } else {
                wiredInstructions
                    .transition(detailTransition)
            }
        }
        .padding(22)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .animation(panelAnimation, value: appState.connectionMode)
    }

    private var wirelessInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            instructionRow(number: "1", title: "打开控制中心") {
                instructionText("在屏幕右上角往下拉（有 Home 键的设备从底部上滑）")
            }
            instructionRow(number: "2", title: "点「屏幕镜像」") {
                ScreenMirroringButton()
            }
            instructionRow(number: "3", title: "选择「\(displayName)」") {
                instructionText("设备需要与 Mac 连接到可以互相访问的局域网。显示名可以在设置里改。")
            }
        }
    }

    private var wiredInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            instructionRow(number: "1", title: "用数据线连接 iPad 和 Mac") {
                instructionText("使用支持数据传输的 USB-C 或 Lightning 线，无需连接同一个 Wi-Fi。")
            }
            instructionRow(number: "2", title: "解锁 iPad，点「信任」") {
                instructionText("在 iPad 上确认「信任此电脑」，并按提示输入设备密码。")
            }
            instructionRow(number: "3", title: "允许访问后，画面自动出现") {
                instructionText("macOS 将有线画面归为相机输入，请允许镜投访问相机。无需在 iPad 上打开「屏幕镜像」。")
            }
            Divider().overlay(Color.white.opacity(0.08))
            wiredDeviceControls
        }
    }

    private func instructionText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
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
                    Button("打开相机权限设置") { openCameraPrivacySettings() }
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

    private func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    private func instructionRow<Content: View>(number: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                content()
            }
            Spacer(minLength: 0)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("设置")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("完成") {
                    dismissSettings()
                }
                .buttonStyle(SoftButtonStyle())
                .foregroundStyle(.white.opacity(0.7))
            }

            connectionPicker

            connectionSettings

            HStack {
                if appState.isReceiverActive {
                    Button(appState.connectionMode == .usb ? "停止有线投屏" : "停止广播") {
                        appState.stopReceiver()
                    }
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

            advancedSettings

            versionRow

            if let error = appState.lastError, appState.status == .failed || appState.status == .missingEngine {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
        .animation(panelAnimation, value: appState.connectionMode)
    }

    private var connectionSettings: some View {
        ZStack(alignment: .topLeading) {
            if appState.connectionMode == .wireless {
                wirelessSettings
                    .transition(detailTransition)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    wiredDeviceControls
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
                Button(updates.phase == .checking ? "正在检查…" : "检查更新") {
                    updates.check()
                }
                .disabled(updates.phase == .checking)
            }
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
        }
    }

    private var displayName: String {
        let trimmed = appState.receiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "镜投" : trimmed
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.receiverName = trimmed.isEmpty ? "镜投" : trimmed
        nameDraft = appState.receiverName
    }
}

private struct SoftButtonStyle: ButtonStyle {
    var hoverScale: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        SoftButtonContent(configuration: configuration, hoverScale: hoverScale)
    }
}

private struct SoftButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let hoverScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : hovered ? 1 : 0.88) : 0.45)
            .scaleEffect(reduceMotion || !isEnabled ? 1 : configuration.isPressed ? 0.98 : hovered ? hoverScale : 1)
            .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.16), value: hovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

private struct ScreenMirroringButton: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("屏幕镜像")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("控制中心里就是这个按钮")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                Text("图标可能略有不同，名字一定是「屏幕镜像」")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }
}
