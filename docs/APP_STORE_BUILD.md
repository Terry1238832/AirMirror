# 商店渠道构建

商店上架名为「镜投:专业屏幕镜像软件」，应用内使用短名称「镜投」。商店配置面向 Apple 芯片、macOS 14+；不影响 GitHub 渠道的仓库入口与自动粘贴功能。

## 环境

- Xcode 与命令行工具、Python 3.12+、CMake、pkgconf（当前脚本使用 `/opt/homebrew/bin/pkgconf`）。
- 钥匙串中已有可用的 Apple Development 身份。脚本只选择现有证书，不新建证书或修改开发者账号。
- 首次构建下载约 1 GB 的官方 GStreamer SDK 安装包及 libplist 源码，并在 `Vendor/StoreGStreamer` 解包；不会运行安装器或安装到系统目录。

依赖 URL、SHA-256、版本和 UxPlay 提交固定在 `Config/store-runtime-lock.json`。脚本隔离 SDK 的 pkg-config 路径，将 libplist 和 OpenSSL 静态链接进 helper，再打包所需的 GStreamer 动态库和插件。不会借用本机 Homebrew 的运行时；曾发现本机 Homebrew 库要求 macOS 27，不能用于标称 14+ 的商店包。

## 本地沙盒测试

```sh
./scripts/build_app_store.sh --local
```

产物：`build/StoreSandbox/Build/Products/AppStore/AirMirror.app`。本地测试 Bundle ID 为 `com.liangyu.airmirror.mas`，与正式应用隔离偏好及容器；测试时退出其他无线接收端，避免端口和名称混淆。

主程序启用 App Sandbox、网络收发、USB、相机及音频输入权限。helper 位于 `Contents/MacOS/uxplay`，仅使用 `app-sandbox` 和 `inherit` 两项 entitlement；主程序、helper 和动态库用同一团队签名，不关闭库验证。socket、配置和插件缓存位于沙盒可用目录。运行时不从 PATH、Homebrew 或外部插件目录回退。

商店版的窗贴使用「截图 → 复制 → 用户手动 ⌘V」流程，不包含辅助功能授权、模拟粘贴和自动回车代码。仓库按钮及 GitHub 更新实现也在编译时排除；隐私和开源许可入口保留。

## 归档与分发

```sh
./scripts/build_app_store.sh --archive
```

产物：`build/AppStore/AirMirror.xcarchive`，使用正式 Bundle ID `com.liangyu.airmirror`。该脚本生成的是 **Development 签名归档**，用于检查和后续导出，不能当作已完成商店分发签名或已上传。

在 Xcode Organizer 中选择归档并使用 App Store Connect 分发流程，配置匹配的商店证书、App ID 与 provisioning profile。对导出后的 `.app` 额外执行：

```sh
python3 scripts/validate_store_app.py /absolute/path/to/exported/AirMirror.app --distribution
```

基础验证器检查沙盒权限、helper 继承、统一签名团队、Hardened Runtime、全部打包 Mach-O 的 arm64 架构及最低系统、运行时闭包、资源和渠道代码。`--distribution` 额外检查分发签名类别和描述文件存在；它不能替代 Apple 的证书、描述文件、上传及审核验证。

## 回归与验证边界

```sh
./scripts/test_receiver_restart.sh
./scripts/test_video_bridge.sh
./scripts/test_windowpaste.sh
./scripts/test_store_channel.sh
./scripts/test_window_motion.sh
```

窗口动效测试应在繁重构建结束后单独运行。编译器宏插件、原生窗口和 socket 回归需要允许相应系统调用的本机执行环境。

Mach-O 最低版本检查不能代替 macOS 14 实机验收；还需在干净 Mac 上验证无 Homebrew 环境、首次权限允许/拒绝/撤销、USB 插拔、无线断线重连、旋转、音频、登录启动及快捷键。当前实机状态和剩余事项以 `MAC_APP_STORE_REVIEW.md` 为准。

随包许可文本和运行时清单是核查材料，并非分发授权结论。上架前还需逐项核对 UxPlay GPL、LGPL 组件的完整对应源码交付和商店条款兼容性，以及协议、品牌、隐私标签与加密出口申报。

本地诊断可临时定义 `STORE_DIAGNOSTICS` 查看 helper 输出；原始输出可能包含设备信息，只用于本机排障。发布验证器会拒绝包含该诊断标记的二进制，常规构建保持日志隐私遮蔽。
