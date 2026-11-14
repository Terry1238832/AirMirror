# 镜投 Mac App Store 技术预检

检查日期：2026-11-14。基线：1.1.1 (5) 之后尚未发布的合并源码。上架名为 **镜投:专业屏幕镜像软件**，应用内使用「镜投」短名称；名称稿位于 `docs/app-store/zh-Hans/name.txt`，尚未在 App Store Connect 提交。

**当前状态：已完成主要沙盒和构建改造，尚未达到提交验收。** 真实 USB 投屏及沙盒内截图复制已通过；补齐 HEVC 声明后，真实 iPad 的最高画质无线接收已成功，实际收到 2882 × 2160。无诊断日志的最终候选包也已通过无线重连确认；仍需完整提交前验收，不能据此声明 Apple 审核通过。

## 已完成的技术改造

| 项目 | 当前实现与验证 |
| --- | --- |
| 真正的商店配置 | `AirMirrorStore` scheme / `AppStore` configuration 启用 App Sandbox 与 Hardened Runtime。`Config/AppStoreChannel.xcconfig` 现在包含完整商店配置，不再是仅隐藏按钮的渠道预览。 |
| 渠道隔离 | 商店主二进制不含仓库按钮 URL、GitHub 发布接口、辅助功能授权和模拟粘贴实现；三处底部仅保留隐私与许可入口。GitHub 配置保留完整入口与自动粘贴。 |
| 窗贴 | 商店版为截图复制后手动 ⌘V；编译时移除 AX 授权、CGEvent 粘贴和自动回车，忽略旧自动回车偏好。窗贴仍为独立窗口，不影响投屏。 |
| helper 沙盒 | 包内 `Contents/MacOS/uxplay` 使用 `app-sandbox` 与 `inherit` 两项 entitlement；配置、插件注册表、socket 在容器可用路径内。禁止 Homebrew、PATH 引擎及外部插件回退。 |
| 签名与库验证 | 主程序、helper 和全部动态库使用同一真实开发团队签名。未加入临时沙盒例外、关闭库验证或 get-task-allow。修复了初版 ad hoc 库在 Hardened Runtime 下被拒绝装载的问题。 |
| macOS 14 依赖 | 本机 Homebrew 库实际要求 macOS 27。改为隔离官方 GStreamer 1.28.8 SDK，重建 UxPlay / libplist 并打包兼容运行时。锁文件固定下载 SHA-256；实际包共检查 41 个 arm64 Mach-O，最低系统均不高于 14。 |
| 接收端恢复 | 修复“每次进程启动就清空失败次数”造成的无限重启；增加有限次数与退避，稳定运行后可恢复预算。 |
| 归档与门禁 | 新增本地测试 / Archive 脚本、统一签名选择及包校验。归档已构建成功，但当前是 Development 签名，后续仍须商店分发导出、验证和上传。 |
| 许可与隐私 | 保留 WindowPaste MIT、UxPlay GPL 全文、隐私说明及第一方隐私清单；商店包额外包含 SDK 许可目录、运行时版本清单和离线阅读入口。补齐文件不等于完成分发授权审查。 |

Apple 的 helper 文档允许按继承沙盒方式嵌入命令行工具；本项目据此实现，不把子进程本身视为禁止事项。[Apple helper 指南](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app)。商店版本须采用商店更新机制，不能把独立下载构建当作商店产物。[审核规则 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)。

## 实机及回归证据

- 已连接真实 iPad，沙盒版 USB 画面实际显示，收到的画面为 1600 × 1200；窗贴独立窗口能截取该原始帧并复制到剪贴板，显示手动 ⌘V 提示。关闭窗贴后投屏保持运行。
- 统一真实团队签名后，无线 helper 能稳定启动，Bonjour 可发现，父子进程的容器内视频 socket 已实际连通。用户确认曾有流畅画面，但默认 720p 清晰度不足。
- 默认质量改为最高档。2160p 为发给设备的目标请求，不能等同于实际收到的分辨率。用户曾反馈重连自动断开；发现高分辨率请求未同时声明 HEVC 能力，补齐后用户确认画面运行良好。本机窗口实际显示画面，接收端日志确认 HEVC 2882 × 2160 并已开始视频接收；无诊断标记的最终候选包随后也由用户确认能正常显示并保持连接。
- 无诊断日志、统一真实团队签名的最终候选包再次通过 USB 1600 × 1200 和窗贴截图复制；用户随后手动切回无线并确认稳定显示。
- 通过接收端重启预算、视频桥接（USB 合成帧、旋转、背压、旧帧、20 次模式切换）、窗贴（独立来源、原始帧截图、选择身份、隔离偏好、PNG/TIFF 和取消粘贴）、商店复制流程与窗口动效回归。
- 构建包校验通过真实沙盒 entitlement、helper 继承、同团队签名、Hardened Runtime、macOS 最低版本、运行时闭包和资源检查。静态包检查不是最低系统实机测试，也不是 Apple 上传或审核结果。

## 提交前仍需完成

1. **硬件与系统验收**：验证 USB / 无线长时间接收、断线重连、旋转、锁屏、音频、首次权限允许/拒绝/撤销、登录启动及快捷键；在无 Homebrew 的干净 Mac 与 macOS 14 实机测试。不能把当前主机的成功或合成帧回归称为这些项目全部通过。
2. **商店分发账号流程**：已有开发身份可用于本机沙盒测试；尚未配置和验证最终商店分发证书、匹配描述文件、Organizer 导出及 App Store Connect 上传。Developer ID、公证或 Development 签名都不能替代商店分发。[证书说明](https://developer.apple.com/help/account/certificates/certificates-overview/)、[描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)。
3. **授权和源码交付**：UxPlay 固定提交 `59f65c804c16f7f6fc7bce6786d5b1eaaf1bf157`，本地桥接补丁在 `scripts/patches/`。SDK 版本、实际二进制和 FFmpeg 构建选项须与完整对应源码交付方式逐项匹配，核查 GPL / LGPL 与商店条款的兼容性。官方 SDK 的 FFmpeg 许可说明为 LGPL-2.1-or-later，与此前 Homebrew 运行时不同；仍不能据此宣称整个包授权核验结束。也不能仅凭 GPL 标签断言 Apple 必然拒绝。
4. **协议、内容和元数据**：核对第三方协议实现、品牌和内容权利，准确说明受保护视频限制；完成隐私标签、政策 URL、加密出口问卷、地区发行及审核说明。第一方无账号、广告、分析和开发者云端采集；“不收集数据”标签仍须以最终全部依赖为准。[隐私标签说明](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy/)。

第一方 `PrivacyInfo.xcprivacy` 声明无跟踪、无采集和用于应用偏好的 UserDefaults（CA92.1）。不要把 Apple 针对列明平台的 required-reason API 上传规则机械解释为独立的 macOS 拒审结论；以最终归档和 Apple 验证为准。[隐私清单](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)。

## 复现

构建、归档、分发检查和回归命令见 [商店构建说明](APP_STORE_BUILD.md)。本地诊断标记只用于排障，发布门禁拒绝含 `STORE_DIAGNOSTICS` 输出标记的二进制。未执行正式商店上传或提交审核。
