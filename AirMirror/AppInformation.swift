import AppKit
import SwiftUI

/// APP_STORE is a build-time channel choice, never inferred from an absent receipt.
struct RepositoryFooter: View {
    var compact = false
    @State private var document: InformationDocument?

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            #if !APP_STORE
            Link(destination: URL(string: "https://github.com/Terry1238832/AirMirror")!) {
                Label(compact ? "GitHub · AirMirror" : "GitHub · Terry1238832/AirMirror", systemImage: "arrow.up.right.square")
            }
            .help("打开镜投的 GitHub 仓库")
            #endif
            HStack(spacing: 16) {
                Button("隐私说明") { document = .privacy }
                Button("开源许可") { document = .licenses }
            }
            .buttonStyle(.plain)
        }
        .font(compact ? .system(size: 10.5) : .caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .sheet(item: $document) { item in
            InformationDocumentView(document: item)
        }
    }
}

private enum InformationDocument: String, Identifiable {
    case privacy, licenses
    var id: String { rawValue }
    var title: String { self == .privacy ? "隐私说明" : "开源许可" }
    var resources: [String] {
        if self == .privacy { return ["PrivacyPolicy"] }
        var names = ["ThirdPartyNotices", "WindowPaste-LICENSE", "UxPlay-LICENSE"]
        if Bundle.main.url(forResource: "StoreRuntimeNotices", withExtension: "txt") != nil {
            names.append("StoreRuntimeNotices")
        }
        return names
    }
}

private struct InformationDocumentView: View {
    let document: InformationDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(document.title).font(.headline)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(contents)
                    .font(.callout)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if document == .licenses,
               let folder = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: nil) {
                Button("查看运行时许可文件…") { NSWorkspace.shared.open(folder) }
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 560, maxWidth: 640, minHeight: 360, idealHeight: 480)
    }

    private var contents: String {
        document.resources.map { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return "无法读取说明文件，请重新安装镜投。"
            }
            return text
        }.joined(separator: "\n\n────────────────────\n\n")
    }
}
