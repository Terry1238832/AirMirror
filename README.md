# 镜投

让 iPhone 和 iPad 通过无线「屏幕镜像」或 USB 数据线，把画面投到 Mac。

官网：[terry1238832.github.io/AirMirror](https://terry1238832.github.io/AirMirror/)

## 安装

1. 到 [Releases](https://github.com/Terry1238832/AirMirror/releases/tag/v1.1.1) 下载 `AirMirror-1.1.1.dmg`，或从官网下载
2. 把「镜投」拖进「应用程序」
3. 第一次打开如果被系统拦住：按住 Control 点图标，选择「打开」

需要 Apple 芯片的 Mac，macOS 14 或更新。无线投屏时，手机和 Mac 要在同一个可以互相发现的局域网里。

## 1.1.1 更新

设置面板淡入并轻弹展开，连接方式切换和高级选项折叠更加连贯。开始、结束投屏及画面旋转时，窗口会平滑调整尺寸；手动缩放与比例滑块仍保持即时响应。动效会跟随 macOS 的「减少动态效果」设置自动收敛。

## 无线投屏

1. 在镜投中选择「无线投屏」。
2. 将 iPhone / iPad 和 Mac 连接到可以互相发现的同一局域网。
3. 在设备控制中心点「屏幕镜像」，选择「镜投」（或设置中的显示名）。

## USB 有线投屏

学校 Wi-Fi 开启设备隔离、局域网无法互通时，可以使用有线模式：

1. 在镜投中选择「USB 有线」。
2. 使用支持数据传输的 USB-C 或 Lightning 线连接 iPad / iPhone 和 Mac。
3. 解锁设备，确认「信任此电脑」，并允许镜投访问相机，画面将自动出现。

macOS 把 USB 设备屏幕归为相机采集源，因此需要相机权限。有线模式无需同一 Wi-Fi，也无需在 iPad 上打开「屏幕镜像」。插拔后会自动重新检测，可在设备列表中手动选择。若没有显示设备，请确认线缆支持传输数据，并关闭其他正在采集该设备的应用。

在设置中开启「播放设备声音」可以接收设备音频；此选项需要麦克风权限，默认关闭。拒绝音频权限不会阻止画面投屏。受保护的视频内容仍可能无法显示。

有线模式使用 macOS 的 AVFoundation / CoreMediaIO 接口，不依赖 UxPlay。

## 从源码编译

需要 Xcode、Homebrew，以及 `cmake`、`openssl@3`、`gstreamer`、`pkgconf`、`libplist`。

```bash
./release.sh
```

会生成 `dist/镜投-1.1.1.dmg`（发布到 GitHub 时文件名为 `AirMirror-1.1.1.dmg`）。无线画面接收使用 [UxPlay](https://github.com/FDH2/UxPlay) `59f65c8`，改动在 `scripts/patches/`。UxPlay 以 GPL-3.0 发布。
