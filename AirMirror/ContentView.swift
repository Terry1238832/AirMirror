import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var discovery: DiscoveryMonitor
    @ObservedObject private var video: VideoBridge
    @State private var nameDraft: String = ""
    @State private var showSettings = false

    init() {
        _discovery = ObservedObject(wrappedValue: AppState.shared.discovery)
        _video = ObservedObject(wrappedValue: AppState.shared.video)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoCanvas(bridge: video)
                .opacity(video.hasVideo ? 1 : 0)

            if !video.hasVideo {
                waitingLayout
            } else {
                streamingOverlay
            }

            if showSettings {
                settingsOverlay
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 760, minHeight: 620)
        .background(
            WindowAspectLock(
                streaming: video.hasVideo,
                videoSize: video.videoSize,
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
                showSettings = false
            }
        }
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
                showSettings = true
            } label: {
                Label("设置", systemImage: "gearshape")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
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
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 40)
            Spacer()
        }
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    commitName()
                    showSettings = false
                }
            ScrollView(.vertical, showsIndicators: false) {
                settingsCard
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28)
                    .padding(.top, 48)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            Text("等待投屏")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(statusLine)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))

            if let pin = appState.pinCode {
                Text("配对码 \(pin)")
                    .font(.system(.title2, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            }

            instructionCard
                .padding(.top, 6)
        }
        .padding(.horizontal, 36)
    }

    private var statusLine: String {
        if discovery.isVisibleOnLan || appState.status == .advertising || appState.status == .starting {
            return "已在局域网广播，手机现在就能搜到"
        }
        return appState.statusText
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            instructionRow(number: "1", title: "打开控制中心") {
                Text("在屏幕右上角往下拉（有 Home 键的设备从底部上滑）")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }
            instructionRow(number: "2", title: "点「屏幕镜像」") {
                ScreenMirroringButton()
            }
            instructionRow(number: "3", title: "选择「\(displayName)」") {
                Text("名字可以在下面的设置里改")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .padding(22)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
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
                    commitName()
                    showSettings = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
            }

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

            HStack {
                if appState.isAdvertising || appState.status == .starting {
                    Button("停止广播") { appState.stopReceiver() }
                } else {
                    Button("开始广播") {
                        commitName()
                        appState.startReceiver()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Button("重新广播") {
                    commitName()
                    appState.restart()
                }
                .disabled(appState.status == .missingEngine)
            }

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
