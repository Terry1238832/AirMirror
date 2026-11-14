# AirPlay 接收 SDK 询问草稿

状态：未发送。用于蓝莓投屏或 Tatvik / Ubiquitous AI 等商业候选；厂商报价和回复不在此文件内。

主题：Native macOS AirPlay screen-mirroring receiver SDK — evaluation and Mac App Store redistribution

Hello,

We are evaluating an AirPlay screen-mirroring receiver SDK for AirMirror, a native macOS utility. Users must be able to connect from the standard iPhone/iPad Control Center Screen Mirroring interface without installing a companion sender application.

Please provide the following before integration:

1. A macOS arm64 evaluation SDK or source package, API headers, sample integration and minimum macOS version. Our target is macOS 14+ on Apple silicon.
2. Written licensing terms that explicitly cover embedding, signing and distributing the SDK and its actual dependencies inside our paid Mac App Store application. Please also state whether a separate GitHub distribution is allowed and how updates are licensed.
3. The SDK's third-party component inventory, exact licenses and relevant copyright/provenance documentation, including the pairing/FairPlay interoperability implementation. Please identify any copyleft requirements and any additional rights or approvals we must obtain. A general “commercial use” statement alone is insufficient for assessing this distribution.
4. App Sandbox and Hardened Runtime compatibility: bundled dependencies only, no external installer or Homebrew runtime, no temporary sandbox exceptions, and no need to disable library validation. Please identify all required entitlements, system permissions and signing constraints.
5. APIs for starting/stopping the receiver, configuring its display name, pairing/PIN, resolution and frame-rate negotiation, reporting connection status, and delivering encoded H.264/HEVC or decoded video frames plus audio. Our app displays video in its own window and offers screenshots from the received frames.
6. Current iOS/iPadOS compatibility and supported codecs, orientation changes, reconnection behavior and optional audio. Please distinguish requested resolution from actual negotiated resolution.
7. Any activation network calls, analytics, telemetry, stored identifiers or cloud relay requirements. Local video processing and offline use after any permitted activation are important for our application.
8. Evaluation restrictions and expiry, pricing model, royalties or per-user fees, support/update terms, and what documentation you provide for an App Review inquiry.

Please confirm the precise licensee/entity details you require. We can supply those separately after reviewing the terms. We are not requesting access to protected streaming-service content or removal of DRM playback restrictions.

Thank you.

## 取得材料后的验收顺序

许可与来源确认 → API/架构和依赖静态检查 → 隔离评估原型 → 原始画面接入现有渲染器 → 统一签名与沙盒 → USB/无线切换与窗贴回归 → 真实 iPad 连接/重连/旋转/声音 → 干净 macOS 14 → 最终商店分发验证。

取得可执行的评估包不等于获得生产发行许可；通过功能测试也不等于完成授权或 Apple 审核。
