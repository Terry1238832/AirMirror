import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var discovery: DiscoveryMonitor
    @ObservedObject private var video: VideoBridge
    @State private var showHelp = false

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
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.opacity)
                } else {
                    streamingOverlay
                        .transition(.opacity)
                }
            }
            .animation(fadeAnimation, value: video.hasVideo)
        }
        .preferredColorScheme(.dark)
        .onChange(of: language.selection) { _, _ in MirrorWindowRegistry.window?.title = AppBrand.name }
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
        .onChange(of: video.hasVideo) { _, streaming in
            if streaming {
                withAnimation(panelAnimation) {
                    showHelp = false
                }
            }
        }
        .onExitCommand {
            if showHelp { showHelp = false }
        }
    }

    private var fadeAnimation: Animation { .easeInOut(duration: reduceMotion ? 0.1 : 0.2) }
    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.36, dampingFraction: 0.9)
    }
    private var detailTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6))
    }

    private func presentSettings() {
        showHelp = false
        MirrorSettingsWindowController.shared.show()
    }

    private var waitingLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                helpButton
            }
            .padding(.horizontal, 16)
            .frame(height: 36)

            // Keep SwiftUI's fitting size from fighting the native window aspect lock.
            // PINs and errors can scroll in this area without displacing the footer.
            GeometryReader { area in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 4)
                        waiting

                        connectionChoices
                            .padding(.top, 20)

                        HStack(spacing: 32) {
                            auxiliaryMenu(compact: false)
                            Button {
                                presentSettings()
                            } label: {
                                Label(L10n.tr("设置"), systemImage: "gearshape")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .buttonStyle(SoftButtonStyle())
                        }
                        .padding(.top, 16)
                        Spacer(minLength: 10)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: area.size.height)
                }
            }
            RepositoryFooter(compact: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
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
                helpButton
                auxiliaryMenu(compact: true)
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

    private func auxiliaryMenu(compact: Bool) -> some View {
        Menu {
            Button(L10n.tr("窗贴 · 截图与粘贴…")) { WindowPasteWindowController.shared.show() }
        } label: {
            if compact {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.white).padding(8)
                    .background(.black.opacity(0.45), in: Circle())
            } else {
                Label(L10n.tr("辅助功能"), systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.58))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.tr("辅助功能"))
        .help(L10n.tr("辅助功能：窗贴截图与粘贴"))
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            Image(systemName: appState.connectionMode.symbol)
                .font(.system(size: 32, weight: .medium))
                .frame(height: 38)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .animation(fadeAnimation, value: appState.connectionMode)

            Text(L10n.tr("等待投屏"))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .help(statusLine)

            if appState.connectionMode == .wireless, let pin = appState.pinCode {
                Text(L10n.tr("配对码 %1$@", String(describing: pin)))
                    .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .transition(detailTransition)
            }
            if appState.status == .failed || appState.status == .missingEngine || appState.wiredPermissionDenied {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .animation(fadeAnimation, value: appState.pinCode)
    }

    private var connectionChoices: some View {
        HStack(spacing: 28) {
            ForEach(ConnectionMode.allCases) { mode in
                let selected = appState.connectionMode == mode
                Button {
                    appState.connectionMode = mode
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.62))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white.opacity(selected ? 0.12 : 0.06), lineWidth: 1)
                        )
                }
                .buttonStyle(SoftButtonStyle(hoverScale: 1.015))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(selected ? L10n.tr("已选择") : L10n.tr("未选择"))
            }
        }
        .frame(maxWidth: 312)
        .padding(.horizontal, 28)
        .animation(fadeAnimation, value: appState.connectionMode)
    }

    private var helpButton: some View {
        Button {
            showHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(SoftButtonStyle())
        .accessibilityLabel(L10n.tr("投屏教程"))
        .help(L10n.tr("投屏教程与连接帮助"))
        .background(HelpPanelAnchor(isPresented: $showHelp, content: AnyView(
            helpContents.environmentObject(appState).preferredColorScheme(.dark).appLanguageEnvironment()
        )).allowsHitTesting(false))
    }

    private var helpContents: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(appState.connectionMode == .usb ? L10n.tr("USB 有线投屏") : L10n.tr("无线投屏"))
                    .font(.headline)
                Spacer()
                Button { showHelp = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(SoftButtonStyle())
                .accessibilityLabel(L10n.tr("关闭教程"))
            }
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            instructionCard
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(width: 360)
    }

    private var statusLine: String {
        if appState.connectionMode == .wireless, discovery.isVisibleOnLan,
           appState.status == .advertising {
            return L10n.tr("已可被局域网内的 iPhone / iPad 搜索到")
        }
        return appState.statusText
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
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 26)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .animation(panelAnimation, value: appState.connectionMode)
    }

    private var wirelessInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            instructionRow(number: "1", title: L10n.tr("打开控制中心")) {
                instructionText(L10n.tr("iPhone X 及更新机型、iPadOS：右上角下拉。有 Home 键的 iPhone 或更早的 iPad：底部上滑。"))
            }
            instructionRow(number: "2", title: L10n.tr("按系统版本选择图标")) {
                ScreenMirroringButtons()
            }
            instructionRow(number: "3", title: L10n.tr("选择「%1$@」", String(describing: appState.receiverName))) {
                instructionText(L10n.tr("设备需要与 Mac 连接到可以互相访问的局域网。显示名可以在设置里改。"))
            }
        }
    }

    private var wiredInstructions: some View {
        VStack(alignment: .leading, spacing: 18) {
            instructionRow(number: "1", title: L10n.tr("用数据线连接 iPad 和 Mac")) {
                instructionText(L10n.tr("使用支持数据传输的 USB-C 或 Lightning 线，无需连接同一个 Wi-Fi。"))
            }
            instructionRow(number: "2", title: L10n.tr("解锁 iPad，点「信任」")) {
                instructionText(L10n.tr("在 iPad 上确认「信任此电脑」，并按提示输入设备密码。"))
            }
            instructionRow(number: "3", title: L10n.tr("允许访问后，画面自动出现")) {
                instructionText(L10n.tr("macOS 将有线画面归为相机输入，请允许镜投访问相机。无需在 iPad 上打开「屏幕镜像」。"))
            }
            Divider().overlay(Color.white.opacity(0.08))
            WiredDeviceControls()
        }
    }

    private func instructionText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
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

}

private struct ScreenMirroringButtons: View {
    @ObservedObject private var language = LanguagePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                iconExample(
                    symbol: "rectangle.on.rectangle",
                    title: L10n.tr("屏幕镜像"),
                    versions: L10n.tr("iOS 11 及以后\n所有 iPadOS 版本")
                )
                iconExample(
                    symbol: "airplayvideo",
                    title: L10n.tr("AirPlay / 镜像"),
                    versions: L10n.tr("iOS 10 及更早\n旧版入口")
                )
            }
            Text(L10n.tr("iOS / iPadOS 18、26、27 都选双矩形。新版中的屏幕＋三角是视频播放入口。"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconExample(symbol: String, title: String, versions: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Text(versions)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
