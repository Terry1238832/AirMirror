// Adapted from WindowPaste (MIT), upstream d8f6bcb86a419b410518264798f5931b2d3344d3.
import AppKit
import SwiftUI

struct WindowPasteView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    @EnvironmentObject private var appState: WindowPasteState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Toggle(L10n.tr("启用窗贴快捷键"), isOn: Binding(get: { appState.isEnabled }, set: { appState.setEnabled($0) }))
                howTo
                shortcut
                targetPicker
                permissions
                extras
                if let message = appState.lastMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Divider()
                RepositoryFooter()
            }
            .padding(22)
        }
        .frame(minWidth: 460, minHeight: 560)
        .appLanguageEnvironment()
        .onChange(of: language.selection) { _, _ in
            WindowPasteWindowController.shared.window?.title = L10n.tr("窗贴 · 镜投辅助功能")
            Task { await appState.refreshWindows() }
        }
        .onAppear {
            appState.refreshPermissions()
            appState.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let previouslyAllowed = appState.hasScreenRecording
            appState.refreshPermissions()
            if !previouslyAllowed, appState.hasScreenRecording { Task { await appState.refreshWindows() } }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 48, height: 48)
                .background(Color.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("窗贴 · 镜投辅助功能"))
                    .font(.title2.weight(.semibold))
                #if APP_STORE
                Text(L10n.tr("按下 %1$@ 复制目标窗口截图，再按 ⌘V 粘贴", String(describing: appState.hotKey.displayName)))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                #else
                Text(L10n.tr("按下 %1$@，截取目标窗口并粘贴到当前光标处", String(describing: appState.hotKey.displayName)))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                #endif
                Text(L10n.tr("独立窗口，关闭后快捷键仍可使用，不影响投屏。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var howTo: some View {
        GroupBox(L10n.tr("怎么用")) {
            VStack(alignment: .leading, spacing: 8) {
                labeled("1", L10n.tr("保持镜投投屏中，或选择其他要截取的软件和窗口"))
                labeled("2", L10n.tr("如果有多个窗口，在下面点选要截取的那个"))
                #if APP_STORE
                labeled("3", L10n.tr("按下 %1$@ 截图复制，再到聊天框、文档中按 ⌘V 粘贴", String(describing: appState.hotKey.displayName)))
                #else
                labeled("3", L10n.tr("把光标放到聊天框、文档等要插入图片的位置，按下 %1$@", String(describing: appState.hotKey.displayName)))
                #endif
                if appState.hotKey.isDefault {
                    Text(L10n.tr("默认快捷键会占用系统自带的「切换当前应用窗口」。可在下面改成别的组合。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shortcut: some View {
        GroupBox(L10n.tr("快捷键")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        #if APP_STORE
                        Text(L10n.tr("截取并复制")).font(.headline)
                        #else
                        Text(L10n.tr("截取并粘贴"))
                            .font(.headline)
                        #endif
                        Text(appState.isRecordingHotKey
                             ? L10n.tr("按下新的组合键，Esc 取消")
                             : L10n.tr("点右边按钮后按下新组合。默认是 Command+·"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appState.toggleHotKeyRecording()
                    } label: {
                        Text(appState.isRecordingHotKey ? L10n.tr("按下组合键…") : appState.hotKey.displayName)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.isRecordingHotKey ? .teal : nil)
                    .accessibilityLabel(appState.isRecordingHotKey ? L10n.tr("正在录制快捷键") : L10n.tr("当前快捷键 %1$@", String(describing: appState.hotKey.displayName)))
                    .accessibilityHint(L10n.tr("点按后按下新的组合键。和系统或其他软件冲突时不会保存。"))
                }

                if !appState.hotKey.isDefault {
                    Button(L10n.tr("恢复默认 ⌘·")) {
                        appState.restoreDefaultHotKey()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.teal)
                    .font(.caption.weight(.medium))
                }

                if let warning = appState.hotKeyWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var targetPicker: some View {
        GroupBox(L10n.tr("截取哪个窗口")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L10n.tr("目标应用"), selection: targetBinding) {
                    ForEach(appState.runningApps()) { app in
                        Text(app.displayName).tag(app)
                    }
                }
                .labelsHidden()

                HStack {
                    Text(L10n.tr("窗口"))
                        .font(.headline)
                    Spacer()
                    if appState.isRefreshingWindows {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button(L10n.tr("刷新")) {
                        Task { await appState.refreshWindows() }
                    }
                    .disabled(appState.isRefreshingWindows)
                }

                windowChoiceRow(
                    id: 0,
                    title: appState.targetApp.isMirror ? L10n.tr("自动选择投屏画面") : L10n.tr("自动选择最大窗口"),
                    subtitle: appState.targetApp.isMirror ? L10n.tr("只截取设备画面，不包含窗贴面板") : L10n.tr("适合只有一个窗口的软件"),
                    preview: nil,
                    selected: appState.selectedWindowID == 0
                )

                if appState.availableWindows.isEmpty {
                    Text(appState.targetApp.isMirror
                         ? L10n.tr("请打开镜投的投屏窗口，然后刷新。")
                         : appState.hasScreenRecording
                         ? L10n.tr("没有找到 %1$@ 的窗口。请确认软件已打开，再点刷新。", String(describing: appState.targetApp.name))
                         : L10n.tr("需要屏幕录制权限后，才能列出各个窗口。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.availableWindows) { window in
                        windowChoiceRow(
                            id: window.windowID,
                            title: window.displayName,
                            subtitle: nil,
                            preview: appState.windowPreviews[window.windowID],
                            selected: appState.selectedWindowID == window.windowID
                        )
                    }
                }

                if appState.selectedWindowID != 0,
                   !appState.availableWindows.contains(where: { $0.windowID == appState.selectedWindowID }) {
                    Text(L10n.tr("已选择的窗口当前不可用，请刷新后重新选择。"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = appState.windowLoadError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }

                Button(appState.isBusy ? L10n.tr("正在截取…") : L10n.tr("复制截图")) {
                    appState.copyScreenshot()
                }
                .disabled(appState.isBusy)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissions: some View {
        GroupBox(L10n.tr("权限")) {
            VStack(alignment: .leading, spacing: 12) {
                if WindowPasteCaptureService.supportsDirectMirrorCapture {
                    #if APP_STORE
                    Text(L10n.tr("镜投自身的投屏画面直接从接收端读取，无需屏幕录制权限。截图复制后由你手动粘贴。"))
                        .font(.caption).foregroundStyle(.secondary)
                    #else
                    Text(L10n.tr("镜投自身的投屏画面直接从接收端读取，无需屏幕录制权限。自动粘贴仍需辅助功能权限。"))
                        .font(.caption).foregroundStyle(.secondary)
                    #endif
                }
                permissionRow(
                    title: L10n.tr("屏幕录制（其他应用）"),
                    detail: L10n.tr("截取其他应用的窗口时需要。请为「镜投」授权，独立版窗贴的授权不会共用。"),
                    granted: appState.hasScreenRecording,
                    actionTitle: appState.hasScreenRecording ? L10n.tr("已开启") : L10n.tr("去开启")
                ) {
                    WindowPastePermissionService.requestScreenRecording()
                    WindowPastePermissionService.openScreenRecordingSettings()
                }

                #if !APP_STORE
                permissionRow(
                    title: L10n.tr("辅助功能权限"),
                    detail: L10n.tr("用来把截图自动粘贴到当前光标位置。没有此权限时仍会复制到剪贴板"),
                    granted: appState.hasAccessibility,
                    actionTitle: appState.hasAccessibility ? L10n.tr("已开启") : L10n.tr("去开启")
                ) {
                    WindowPastePermissionService.requestAccessibility()
                    WindowPastePermissionService.openAccessibilitySettings()
                }
                #endif
            }
            .padding(.vertical, 4)
        }
    }

    private var extras: some View {
        GroupBox(L10n.tr("其他")) {
            VStack(alignment: .leading, spacing: 10) {
                #if !APP_STORE
                Toggle(L10n.tr("自动回车"), isOn: autoReturnBinding)
                    .padding(.vertical, 2)
                Text(L10n.tr("粘贴截图后再按一次回车，适合微信等聊天框直接发出去。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
                Toggle(L10n.tr("登录 Mac 时自动打开镜投"), isOn: launchAtLoginBinding)
                    .padding(.vertical, 2)
                Text(L10n.tr("此选项控制镜投整体。建议先把镜投放到「应用程序」文件夹。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetBinding: Binding<WindowPasteTargetApp> {
        Binding(
            get: { appState.targetApp },
            set: { appState.setTarget($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
        )
    }

    private var autoReturnBinding: Binding<Bool> {
        Binding(
            get: { appState.autoPressReturn },
            set: { appState.setAutoPressReturn($0) }
        )
    }

    private func windowChoiceRow(
        id: UInt32,
        title: String,
        subtitle: String?,
        preview: NSImage?,
        selected: Bool
    ) -> some View {
        Button {
            appState.setSelectedWindow(id: id)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                previewView(preview, placeholder: id == 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.teal : Color.secondary)
                    .font(.title3)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.teal.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.teal.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func previewView(_ image: NSImage?, placeholder: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if placeholder {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func labeled(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.caption.weight(.bold))
                .foregroundStyle(.teal)
                .frame(width: 18, height: 18)
                .background(Color.teal.opacity(0.15), in: Circle())
            Text(text)
                .font(.callout)
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .disabled(granted)
        }
    }
}
