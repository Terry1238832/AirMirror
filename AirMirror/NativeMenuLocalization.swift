import AppKit

@MainActor
enum NativeMenuLocalization {
    private static var updating = false
    private static let titleKeys: [String: String] = {
        let keys = ["编辑", "显示", "窗口", "帮助", "服务", "撤销", "重做", "剪切", "复制", "粘贴", "粘贴并匹配样式", "删除", "全选", "最小化", "缩放", "进入全屏幕", "退出全屏幕", "全部置于前面", "隐藏其他", "全部显示"]
        var result: [String: String] = ["拷贝": "复制", "拷貝": "复制"]
        for key in keys {
            for language in AppLanguage.supported {
                result[L10n.value(key, language: language).lowercased()] = key
            }
        }
        return result
    }()

    static func update() {
        guard !updating, let main = NSApp.mainMenu else { return }
        updating = true
        defer { updating = false }
        if main.items.first?.title != AppBrand.name { main.items.first?.title = AppBrand.name }
        if main.items.first?.submenu?.title != AppBrand.name { main.items.first?.submenu?.title = AppBrand.name }
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if let key = titleKeys[item.title.lowercased()] {
                    let title = L10n.tr(key)
                    if item.title != title { item.title = title }
                    if item.submenu?.title != title { item.submenu?.title = title }
                }
                if let action = item.action {
                    var title = item.title
                    switch NSStringFromSelector(action) {
                    case "hide:": title = L10n.tr("隐藏 %1$@", AppBrand.name)
                    case "hideOtherApplications:": title = L10n.tr("隐藏其他")
                    case "unhideAllApplications:": title = L10n.tr("全部显示")
                    case "terminate:": title = L10n.tr("退出 %1$@", AppBrand.name)
                    case "orderFrontStandardAboutPanel:": title = L10n.tr("关于 %1$@", AppBrand.name)
                    case "undo:": title = L10n.tr("撤销")
                    case "redo:": title = L10n.tr("重做")
                    case "cut:": title = L10n.tr("剪切")
                    case "copy:": title = L10n.tr("复制")
                    case "paste:": title = L10n.tr("粘贴")
                    case "pasteAsPlainText:": title = L10n.tr("粘贴并匹配样式")
                    case "selectAll:": title = L10n.tr("全选")
                    case "delete:": title = L10n.tr("删除")
                    case "performMiniaturize:": title = L10n.tr("最小化")
                    case "performZoom:": title = L10n.tr("缩放")
                    case "toggleFullScreen:": title = L10n.tr(NSApp.mainWindow?.styleMask.contains(.fullScreen) == true ? "退出全屏幕" : "进入全屏幕")
                    case "arrangeInFront:": title = L10n.tr("全部置于前面")
                    default: break
                    }
                    if item.title != title { item.title = title }
                }
                if let submenu = item.submenu { visit(submenu) }
            }
        }
        visit(main)
        if NSApp.helpMenu?.title != L10n.tr("帮助") { NSApp.helpMenu?.title = L10n.tr("帮助") }
    }
}
