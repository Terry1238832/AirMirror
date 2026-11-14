# 无线接收实现替换评估

检查日期：2026-11-14。基线：`b2c8bce39f436f67c3ca1c52c4b8fae300d32817`。

## 结论

**本轮没有完成无线引擎替换。** 已筛选下列公开实现和商业 SDK，并下载一个公开 macOS 演示进行二进制静态检查；未找到已具备原生 Apple 芯片接入材料、来源可确认且明确覆盖本项目商店再分发的现成候选。此结论限定于本次实际核查的资料，不表示不存在其他商业方案。

当前正式代码仍使用原 UxPlay 固定提交。没有把上层 MIT/Apache 标识当作底层所有代码的许可，也没有将评估演示放入应用包。不能把当前功能测试结果称为「新引擎测试通过」。

用户确认的约束：继续从 iPad 系统控制中心「屏幕镜像」连接；不改成需要安装配套 iPad App 的 ReplayKit 传输方案。自研原生 AirPlay 兼容实现仍需核清协议、握手和代码来源等事项，不能以「从头写」作为所有发行权利已经清楚的证明。

## 候选及证据

| 候选 | 实际核查 | 接入决定 |
| --- | --- | --- |
| [MirrorCast](https://github.com/shigeosapsycho/mirrorcast#install-an-engine) | 上层 MIT，README 指明实际画面依赖 UxPlay/RPiPlay；内置模式仅发现与握手，不能解码显示 | 无法消除现有引擎许可问题，不替换 |
| [Java AirPlay](https://github.com/serezhka/java-airplay) | `61f6be78ff4f22133987a38d9fdb95da47428be6`；根 MIT。FairPlayScrambler 与 SapHash 中可见与现有 PlayFair 实现相同的独特注释及相似计算结构，来源许可不能仅凭根 MIT 判清。另需 Java 运行时 | 不作为本次商店替代；未认定其违法，也未把根 MIT 认作全部来源已获许可 |
| [AtrisCast](https://github.com/merteren97/AtrisCast/blob/main/THIRD_PARTY_NOTICES.md) | Android/Kotlin Apache-2.0；第三方通知明确 native FairPlay bridge 使用 LGPL-3.0-or-later 的 shairplay-rust；项目处于早期实机验证阶段 | 无原生 macOS SDK，仍有 LGPL 和移植工作，不直接替换 |
| [APSDK](https://github.com/air-display/apsdk-public) | 根 GPL-2.0；README 指明私有 FairPlay 子模块不可公开获取，空实现可编译但无法正常工作 | 同时存在许可及核心不可用问题，不替换 |
| [蓝莓 Airplay-SDK](https://github.com/xfirefly/Airplay-SDK) | 商业源码/SDK 联系销售；公开 macOS `airdemo` 下载后为 x86_64，minOS 13，依赖 `/usr/local/opt/sdl2` 及 `/usr/local/opt/ffmpeg@4`；目录未提供可嵌入库、头文件或本项目再分发合同 | 保留为厂商询问候选；当前演示不能直接放入 arm64、自包含沙盒包 |
| [Tatvik / Ubiquitous AI Mirroring SDK](https://www.ubiquitous-ai.com/products/tv-apreceiver/) | 官方产品页列出 Apple MAC PC、原始/编码数据输出、库/头文件/API 手册，评估版需向厂商申请；未取得实际包或本项目商店许可条款 | 保留为厂商询问候选；不能依据产品宣传认定已获再分发授权 |
| [AirServer](https://support.airserver.com/support/solutions/articles/43000512398-which-license-should-i-choose-what-license-types-are-there-) | 公开页面为终端软件激活许可；企业用途要求联系厂商，未取得嵌入 SDK、接口或再分发合同 | 终端软件使用许可不足以作为嵌入镜投的依据 |
| [NXP AirPlay SDK](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors/i-mx-8-applications-processors/airplay-software-development-kit-sdk:AIRPLAY-SDK) | 产品面向 i.MX 音频平台，交付前验证 MFi 身份 | 不匹配当前 macOS 整屏镜像接收需求；不据此推定 Mac 软件必须取得这一硬件 SDK |

Java 运行时的额外商店问题核对了 [Apple Developer Program License Agreement 3.3.1(A)](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) 的当前公开文本。没有尝试通过打包 JRE 或机械翻译其 FairPlay 实现来规避接入条件。

还核查了 [DeviceDiscoveryExtension](https://developer.apple.com/documentation/devicediscoveryextension)：它用于应用内媒体路由发现，需要发送端应用/扩展配合；当前资料不支持把它当作无需 iPad 配套应用的系统整屏镜像接收 SDK。ReplayKit + 自研协议可以是另一种公开 API 路线，但不满足用户此次确认的连接方式。

## 已检查的演示文件

- 来源：`https://raw.githubusercontent.com/xfirefly/Airplay-SDK/master/macOS%26Linux/airdemo`
- SHA-256：`608364de147ff352295dbf21fe3f80e87f9c02693fe6dc9c4b1c44a02edca3eb`
- 工具：`file`、`otool -L`、`vtool -show-build`。仅静态检查，没有将演示运行、签名或整合为新引擎。
- 临时文件仅在忽略目录 `build/receiver-replacement-research/`；没有发布第三方 SDK 二进制。

## 可继续推进所需的交付物

先取得至少一个候选的 arm64 macOS SDK/源码、真实 API 头文件和文档，以及覆盖实际依赖和本应用 Mac App Store 分发的许可证明。然后才能实施适配、统一签名、沙盒验收及端到端真机测试。

厂商材料检查项与询问草稿见 [SDK 询问稿](SDK-INQUIRY-DRAFT.md)。本轮没有向厂商发送消息、申请账号、接受合同或付款。
