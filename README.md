# 镜投

让 iPhone 和 iPad 用系统自带的「屏幕镜像」，把画面投到 Mac。

官网：[terry1238832.github.io/AirMirror](https://terry1238832.github.io/AirMirror/)

## 安装

1. 到 [Releases](https://github.com/Terry1238832/AirMirror/releases) 下载 `镜投-1.0.0.dmg`，或从官网下载
2. 把「镜投」拖进「应用程序」
3. 第一次打开如果被系统拦住：按住 Control 点图标，选择「打开」

需要 Apple 芯片的 Mac，macOS 14 或更新。手机和 Mac 要在同一个可以互相发现的 Wi-Fi 里。

## 从源码编译

需要 Xcode、Homebrew，以及 `cmake`、`openssl@3`、`gstreamer`、`pkgconf`、`libplist`。

```bash
./release.sh
```

会生成 `dist/镜投-1.0.0.dmg`。画面接收使用 [UxPlay](https://github.com/FDH2/UxPlay) `59f65c8`，改动在 `scripts/patches/`。UxPlay 以 GPL-3.0 发布。
