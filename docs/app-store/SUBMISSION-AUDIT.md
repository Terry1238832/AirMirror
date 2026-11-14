# Mac App Store 提交验收记录

日期：2026-11-14。对象：镜投 1.1.1 (5) 后的当前源码、最新本地沙盒包及 Development 归档。上架名：**镜投:专业屏幕镜像软件**。

结论：**本地技术预检通过，暂不能标记为正式提交就绪。** 未执行 App Store Connect 上传或提交；没有把 Development 归档称为商店分发包。下列账号、授权及实机验收门槛仍需关闭。

## 本轮已完成

| 检查 | 结果与边界 |
| --- | --- |
| 构建 | GitHub Release 构建、本地 AppStore 构建、AppStore Archive 均成功。两渠道共用新图标与语言资源。 |
| 包校验 | 41 个 arm64 Mach-O、最低系统不高于 macOS 14、动态库闭包、同团队签名、Hardened Runtime、主程序沙盒及 helper 继承均通过。未关闭库验证、未使用临时沙盒例外。 |
| 商店渠道隔离 | 主二进制无项目 GitHub 按钮 URL、发布接口、AX 授权或 CGEvent 粘贴实现；底部仅隐私及许可。运行时自包含，不从 Homebrew / PATH 回退。 |
| 公开 API | USB 使用 AVFoundation 与 CoreMediaIO；两个设备枚举 opt-in 常量可在 Xcode SDK 的公开 `CMIOHardwareSystem.h` 找到。包内动态库无 PrivateFrameworks 依赖。此静态检查不能替代 Apple 的私有 API 扫描。 |
| 语言 | 267 条应用文案 × 14 种语言，完整性、格式占位符、离线资源和 4 类权限说明通过校验。实测首次选择默认为系统、完成后不重复出现、设置切换、英/日按钮刷新、阿拉伯语 RTL、品牌默认名称切换。最终测试偏好恢复跟随系统。macOS 管理的标准编辑项、听写等使用系统提供的语言；应用内容与自有菜单切换即时更新。未宣称所有语种经过母语人工审校。 |
| 图标与名称 | 使用用户提供的图形，保留原稿与透明源，验证关于窗口的新图标。自动接收名为「镜投 / 鏡投 / AirMirror - Mac 设备名称」，自定义名称保留。 |
| 回归 | 接收端有限重试、默认名称及语言解析、视频帧/旋转/背压/旧帧/20 次模式切换、窗贴来源与身份隔离、PNG/TIFF、取消粘贴及商店复制流程通过。原生尺寸变化、比例追踪、减少动态效果、滑块、重置及全屏/实时缩放中断的窗口动效回归也通过。 |
| 隐私 | 应用内文本和网页政策已同步增加语言偏好与默认设备名广播说明；公开政策地址检查为 HTTP 200。商店无开发者视频中继、账户、广告、分析服务。当前代码不修改或读取其他应用的语言偏好。 |
| 提交材料 | 准备中英文名称、简介、描述、关键词，以及英文审核步骤。长度校验通过。描述没有承诺固定 4K、远程触控或不存在的录屏功能。 |

此前本机真实 iPad 沙盒验证已通过 USB 1600×1200、截图复制、无线 HEVC 2882×2160，用户确认流畅及重连后稳定。此轮主要改变语言与图标，复用了此前硬件证据；没有把它写成此次重新完成全部硬件矩阵。

## 正式提交前的门槛

1. **商店分发签名与 Apple 验证**：本机可用证书中 Apple Development 3 个，Apple Distribution / 3rd Party Mac Developer Application 为 0。需要匹配正式 App ID 的商店证书与描述文件，使用 Organizer 导出并 Validate App，再验证导出包。未创建证书、修改开发者账号或接受协议。正式上传前确认唯一递增的 Build 号。
2. **开源分发授权与对应源码**：UxPlay 的 GPLv3、SDK 内 LGPL 组件及商店条款尚未完成兼容性确认。MIT 窗贴许可、保留 GPL 文本、独立 helper 进程都不等于此项自动通过。完整对应源码、补丁、构建条件及 LGPL 用户权利的交付方式必须落地；不能把更改根许可证、隐藏许可或关闭库验证当作解决办法。逐项清单见 [源码与许可门槛](SOURCE-COMPLIANCE.md)。需要确认的是发行授权，不是要求开源组件免费或禁止商业收费。
3. **加密出口问卷**：无线 helper 内含非 Apple 系统提供的 OpenSSL 加密实现。不得直接按「只使用系统 HTTPS」填写豁免。应根据实际加密用途与发行地区完成 App Store Connect 问卷及所需文件；当前未擅自填 `ITSAppUsesNonExemptEncryption = false`。
4. **干净系统验收**：在 macOS 14 的 Apple 芯片 Mac、无 Homebrew 环境复测首次权限允许/拒绝/撤销、USB 插拔、无线重连、长时间接收、旋转、锁屏、可选音频、登录启动、快捷键以及退出后的 helper 清理。静态 minOS 与本机当前系统不能替代该验证。
5. **商店资料与权利**：确认图标和宣传素材的发行权，制作不含私人设备信息或无权使用内容的真实操作截图，填写年龄分级、支持 URL、隐私标签、版权、销售地区与审核联系人。国区及其他地区另以实际账号要求为准。本轮没有代填开发者主体或地区申报资料。

这些事项关闭后，再以最终分发包作一次一致性检查并提交审核。Apple 的最终决定无法由本地测试代替。

## 隐私标签填写依据

当前商店代码所见数据流是设备到本机、本机帧或指定窗口到系统剪贴板；未发现向开发者发送画面、音频、截图、窗口标题或设置的功能。按当前实现，“不收集数据”是可准备的申报答案；最终需按实际发布包及全部第三方依赖再次确认。系统通用剪贴板、用户自行安装的剪贴板工具及手动粘贴的接收应用由各自规则处理，不应描述成应用保证数据永不离开设备。

政策候选 URL：<https://terry1238832.github.io/AirMirror/privacy.html>。本轮检查为 HTTP 200；push 后应确认网页日期与应用内一致。隐私 URL 是提交资料，不作为商店应用底部的 GitHub 入口。

## 核对来源

- [Apple 审核规则](https://developer.apple.com/app-store/review/guidelines/)：重点核对完整性、真实元数据、Mac 沙盒、自包含更新与隐私。
- [Apple 应用信息](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)：名称、简介与隐私 URL。
- [Apple 隐私申报](https://developer.apple.com/app-store/app-privacy-details/)：区分本地处理和开发者采集，覆盖依赖。
- [Apple 加密出口说明](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)：含第三方加密实现也须判定申报义务。
- [UxPlay 固定提交的许可](https://github.com/FDH2/UxPlay/blob/59f65c804c16f7f6fc7bce6786d5b1eaaf1bf157/LICENSE)：GPLv3。包内 SDK 许可文本与运行时清单同时作为组件核对材料。
