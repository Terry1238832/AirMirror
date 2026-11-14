# 镜投 Mac App Store 上架预检

检查日期：2026-11-13。范围：镜投与 WindowPaste 合并后的当前源码、Release 应用包和渠道预览构建；版本基线 1.1.1 (5)，合并功能尚未发布新安装包。

**结论：当前不能直接提交。** 本次是准备性检查，没有进行 App Store Connect 上传验证，也没有提交 Apple 审核。以下把明确的技术阻碍、已修正项和仍需人工验证的风险分别列出。

## 上架名称

App Store Connect 简体中文名称：**镜投:专业屏幕镜像软件**（按用户指定保留半角冒号）。名称稿保存在 `docs/app-store/zh-Hans/name.txt`。应用内短名称仍为「镜投」；本次仅记录上架元数据，尚未在 App Store Connect 创建或更改条目。

## 明确阻碍

| 项目 | 本地证据 | 后续处理 |
| --- | --- | --- |
| 沙盒关闭 | `AirMirror/AirMirror.entitlements` 的 app-sandbox 为 false；工程 Debug / Release 的 ENABLE_APP_SANDBOX 为 NO | 建立真正启用沙盒的商店配置，按功能申请必要权限，并重新验证全部工作流。Mac 商店要求适当沙盒化。[Apple 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) |
| 跨应用自动粘贴与回车 | `WindowPasteClipboardService.swift` 调用 CGEvent 并向系统事件流发送 ⌘V / Return；权限服务依赖 AX 授权 | 不能靠开启沙盒开关解决。Apple 的辅助功能文档明确指出控制其他应用的功能不能沙盒化；商店渠道需调整为截图复制后手动粘贴等可支持的设计，再真机验证。当前仍保留完整功能，**没有把渠道预览伪装成可上架版**。[Apple 辅助功能文档（归档）](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Accessibility/cocoaAXIntro/cocoaAXintro.html) |
| 无线引擎的沙盒适配未完成 | `ReceiverEngine.swift` 通过 Process 启动 UxPlay；当前包内 helper 没有沙盒继承 entitlements；`VideoBridge.swift` 使用 `/tmp/airmirror-<pid>.sock`；EngineLocator / ReceiverEngine 允许 Homebrew、PATH 外部引擎与插件回退 | 商店版只运行包内引擎与依赖，改用容器可用路径，审查缓存、socket 和插件装载；按 Apple 文档签名 helper 并继承沙盒或改用合适的 XPC 设计。**子进程本身并非一律禁止。** [Apple helper 指南](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app) |
| 商店分发签名未配置 | 工程采用手动 ad hoc 签名 `-`，没有配置开发团队与商店描述文件；现有应用 TeamIdentifier 未设置 | 本机实际可用证书为 3 个 Apple Development、1 个 Developer ID Application，未发现 Apple Distribution / Mac App Distribution / Mac Installer Distribution 类别。需由开发者账号配置商店分发身份与 provisioning，再 Archive / Validate / Upload；Developer ID 不能代替商店分发。[Apple 证书说明](https://developer.apple.com/help/account/certificates/certificates-overview/)、[商店描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile) |
| 当前发布方式是独立下载 | `build.sh` 构建 arm64 应用并使用 ad hoc 签名，`release.sh` 制作 DMG；不产生商店归档 | 增加 Xcode 商店分发工作流。当前 DMG 不是送审产物。Hardened Runtime / Developer ID 公证也不等于商店审核通过。 |

## 本次已处理

- **合并说明**：README、CHANGELOG 和官网明确镜投与 WindowPaste 已合并到当前源码；窗贴仍是镜投内可独立打开的窗口。公开下载仍指向旧的 v1.1.1，避免误称安装包已包含新功能。
- **渠道入口**：普通 GitHub 构建在等待页最底部、设置底部和窗贴底部显示 `Terry1238832/AirMirror` 仓库链接。`APP_STORE` 构建从编译时去除该 Link、GitHub 更新按钮和 UpdateChecker 的网络实现；隐私与许可入口保留。商店更新须通过商店提供。[Apple 2.4.5(vii)](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)
- **隐私政策**：新增随包离线说明及网页 `https://terry1238832.github.io/AirMirror/privacy.html`，说明画面/音频本地处理、剪贴板、跨应用粘贴、权限撤销、本地偏好与日志、手动 GitHub 更新请求。发布商店时还需填写 App Store Connect 的隐私政策 URL。[Apple 隐私政策字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/)
- **隐私清单**：新增第一方 `PrivacyInfo.xcprivacy`，声明无跟踪、无开发者采集，记录仅用于本应用偏好的 UserDefaults（CA92.1），并核对实际资源入包。Apple 对 required reason API 的说明主要针对 iOS 等列明平台，**不能把 iOS 上传规则机械视作此 macOS 应用的独立拒审结论**；仍需检查最终归档、SDK 清单和 App Store Connect 验证结果。[Apple 隐私清单](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)、[清单位置及有效性](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- **日志隐私**：UxPlay 原始输出和可含用户名的引擎路径从 public 改为 private，避免在常规系统日志导出中明文暴露相关信息。
- **许可入口**：保留 WindowPaste MIT 全文，增加 UxPlay GPL v3 全文和第三方说明，应用内可离线阅读。这只是补齐说明，不代表已完成所有运行时再分发义务。

## 需要人工核查的风险

1. **依赖与授权**：当前包有 61 个动态库（Frameworks 与 GStreamer 插件合计）。UxPlay 固定上游提交为 `59f65c804c16f7f6fc7bce6786d5b1eaaf1bf157`，还需保留 `scripts/patch_uxplay.py` 和 `scripts/patches/` 的改动及完整对应源码交付方式。Homebrew 本机元数据显示 FFmpeg 为 GPL-3.0-or-later，GStreamer / GLib / libplist 含 LGPL，OpenSSL 为 Apache-2.0；这不是完整法律核验。逐一确认实际打包版本、FFmpeg 构建选项、传递依赖、源码提供与商店分发条款的兼容性。不能因 WindowPaste 为 MIT 就把整个包视作 MIT，也不能仅凭 GPL 标签断言 Apple 必然拒绝。
2. **协议及内容权利**：无线接收依赖第三方实现，提交前确认协议实现、品牌/商标、内容权利及分发授权，准确描述受保护视频内容限制。未发现第一方代码明确调用私有 SDK 符号，但这不是对预编译引擎及全部动态库的完整私有 API 认证。
3. **隐私标签**：第一方代码没有账户、广告、分析或开发者云端上传。是否在 App Store Connect 选择「不收集数据」仍须以最终商店包及全部依赖的数据流为准；第一方清单不能替第三方依赖作保证。
4. **目标系统和架构**：当前面向 Apple 芯片、macOS 14+。arm64-only 本身不在本报告中被当作拒审条件，需保证商店说明、截图和设备兼容性一致。测试当前正式 macOS 及最低支持系统；当前 Xcode 27.2 构建成功不等于最低系统实机验证。

## 渠道预览的边界与复现

`Config/AppStoreChannel.xcconfig` **只负责隐藏 GitHub 入口和外部更新实现**，还沿用 Release 的非沙盒功能与构建设置。请勿把这个预览构建上传送审。

```sh
# GitHub 版
xcodebuild -project AirMirror.xcodeproj -scheme AirMirror -configuration Release \
  -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual

# 商店渠道界面预览：仅编译检查，不是正式商店归档
xcodebuild -project AirMirror.xcodeproj -scheme AirMirror -configuration Release \
  -xcconfig Config/AppStoreChannel.xcconfig -derivedDataPath build/StoreChannelDerivedData \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=NO

./scripts/test_video_bridge.sh
./scripts/test_window_motion.sh
./scripts/test_windowpaste.sh
```

这些本机窗口、渲染和 socket 测试需在允许相关系统调用的环境运行；动效回归应在其他繁重构建结束后单独执行，避免调度负载干扰完成时间断言。

## 实机送审前验收与审核说明草案

- 新安装/首次权限授权及拒绝、撤销后重试；分别验证有线、无线、截图、剪贴板、登录启动，以及关闭窗贴/主窗口/退出后的进程生命周期。
- 真实 iPad / iPhone：有线连接、信任提示、插拔、锁屏、旋转、可选音频；无线配对、断线重连及设备隔离校园网。此次没有连接移动设备，不能把合成帧回归称为完整实机验收。
- 沙盒正式商店包：无 Homebrew 的干净 Mac，全部引擎资源随包可用，不能借 GitHub 版权限或进程工作。最旧支持系统及当前系统均要验证。
- 在 App Store Connect 填写真实截图、年龄分级、分类、支持网址、隐私 URL、加密/出口合规问卷（无线引擎使用 OpenSSL，具体答案需按实际实现判断），以及可重现的审核步骤。未登录 App Store Connect 核对既有记录。
- 审核备注说明无需账户；USB 测试需要支持数据的线缆及解锁、信任的 iPhone / iPad；无线需要可互相发现的局域网；解释相机/可选麦克风权限用途，并列明商店版窗贴最终可用操作及受保护内容限制。必要时提供实际操作视频，不能用视频代替可运行功能。

## 验证记录

- 设置窗口后续调整：移出投屏画面的覆盖面板，改为单实例纵向窗口；已实查分区排版、展开高级设置、滚动到底部、应用菜单重开，以及「完成」和原生关闭命令返回投屏窗口。接收状态仍保持广播；没有连接移动设备进行本轮硬件投屏测试。两渠道编译通过。

- GitHub Release 构建与 `APP_STORE` 渠道预览构建均成功。
- 实际 Mach-O 校验：GitHub 构建含仓库 URL 和发布接口 URL；商店渠道二进制均不含这两个地址。
- 两个应用包内的隐私清单、隐私说明、第三方说明、WindowPaste MIT 与 UxPlay GPL 共 5 项资源均与源码一致，plist 语法校验通过。
- 投屏渲染回归通过（USB 合成帧、旋转、背压、过期帧、20 轮无线/USB 切换）；窗口动效回归通过；窗贴回归通过（独立来源、显示帧截图、旋转、选窗身份、隔离偏好、PNG/TIFF 和取消粘贴）。繁重构建并发时动效计时断言曾超时；完成构建后单独运行通过，未因此修改产品动效。
- 本机 UI 实查：GitHub 版等待页、设置、独立窗贴窗口均有正确仓库链接；商店渠道三处均无仓库入口，设置中也没有检查更新按钮。离线隐私说明可正常打开、阅读、关闭。此次未授予新的屏幕录制或辅助功能权限。
- 后续精简主界面：教程移至右上角问号，无线 / USB 改为间隔 28 pt 的独立按钮；默认窗口 480 × 402，等待页最小短边 300 pt。已检查小窗口及原生放大/还原、两种模式教程的展开和关闭、设置与独立窗贴入口；修正了首轮实窗检查发现的 SwiftUI 最小布局与原生窗口约束循环。最终两渠道构建及窗口动效回归再次通过。
- 已用本次 GitHub 构建更新 `/Applications/镜投.app`，保留旧版到废纸篓以便恢复，并在渠道预览完成后重新打开安装版。

尚未执行真正沙盒包的硬件验收、正式签名归档校验、Transporter/Organizer 上传或 Apple 审核。
