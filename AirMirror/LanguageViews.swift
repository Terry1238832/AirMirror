import AppKit
import SwiftUI

struct AppLanguageEnvironment: ViewModifier {
    @ObservedObject private var language = LanguagePreferences.shared
    func body(content: Content) -> some View {
        content
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

extension View {
    func appLanguageEnvironment() -> some View { modifier(AppLanguageEnvironment()) }
}

struct LanguagePicker: View {
    @ObservedObject private var language = LanguagePreferences.shared
    var body: some View {
        Picker(L10n.tr("语言"), selection: Binding(get: { language.selection }, set: language.select)) {
            Text(L10n.tr("跟随系统")).tag(AppLanguage.system)
            ForEach(AppLanguage.supported) { choice in
                Text(choice.nativeName).tag(choice)
            }
        }
        .pickerStyle(.menu)
    }
}

struct LanguageWelcomeView: View {
    @ObservedObject private var language = LanguagePreferences.shared
    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 64, height: 64)
            }
            Text(L10n.tr("欢迎使用 %1$@", AppBrand.name)).font(.title2.weight(.semibold))
            Text(L10n.tr("默认跟随系统语言，也可以在这里选择。以后可随时在设置中更改。"))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            LanguagePicker()
            Button(L10n.tr("开始使用")) { language.completeSetup() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 400)
        .preferredColorScheme(.dark)
        .appLanguageEnvironment()
    }
}
