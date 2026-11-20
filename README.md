<div align="center">

<img src="showcase/app-icon.png" width="112" height="112" alt="BoltZip" />

# BoltZip ⚡

**快如闪电，通透如玻 —— 让 macOS 压缩像桌面本身一样顺手**

**简体中文** | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md)

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B%20(Apple%20Silicon)-0ea5e9?style=flat-square)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-6366f1?style=flat-square)
[![Release v1.0.4](https://img.shields.io/badge/release-v1.0.4-facc15?style=flat-square)](https://github.com/hwang8859-1/BoltZip/releases/latest)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

<p>
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.4/BoltZip-1.0.4-macOS-arm64.dmg"><strong>⬇️ 直接下载最新版 v1.0.4 (.dmg · Apple Silicon)</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg">🛡 下载兼容版 v0.9.3 (.dmg · Intel / macOS 12–26)</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/latest">📦 GitHub Releases</a>
  &nbsp;·&nbsp;
  <a href="https://122.51.112.183/boltzip/">🌐 在线下载站与演示</a>
</p>

</div>

---

**BoltZip** 是一款专为 **macOS 26.0+（Apple Silicon M 系列 `arm64` 独占优化）** 打造的开源压缩与解压缩工作台。它融合了 Windows 经典压缩工具（7-Zip / WinZip / Bandizip）的高效交互与 macOS 26 原生 **Liquid Glass 液态玻璃** 质感，告别双击即全量解压一地的传统体验。

> 💡 **Intel Mac 或 macOS 12 Monterey ~ macOS 15 用户**：长期兼容版 **v0.9.3 Universal (`arm64 + x86_64`)** 维护在 [`legacy/macos-12`](../../tree/legacy/macos-12) 分支 / [`v0.9.3`](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) Release。

> [!IMPORTANT]
> **当前活跃开发分支：[GitHub 默认 `dev-*` 分支](../../)** · `main` 分支仅用于稳定版本发布且已受保护。提交代码或 PR 请务必保持指向当前默认开发分支，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## ⬇️ 快速下载与安装

| 适用机型与系统 | 推荐版本 | 直接下载链接 | 发布页 |
| :--- | :--- | :--- | :--- |
| **Apple Silicon (M 系列 `arm64`) · macOS 26.0+** | **`v1.0.4`**（最新正式版） | [下载 `.dmg` 安装镜像](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.4/BoltZip-1.0.4-macOS-arm64.dmg) · [便携包 `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.4/BoltZip-1.0.4-macOS-arm64.zip) | [Release v1.0.4 ↗](https://github.com/hwang8859-1/BoltZip/releases/latest) |
| **Intel (`x86_64`) 或 macOS 12.0–15 / 26+** | **`v0.9.3`**（Universal 全兼容版） | [下载 `.dmg` 兼容镜像](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg) · [便携包 `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.zip) | [Release v0.9.3 ↗](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) |

- **安装步骤**：打开下载的 `.dmg` 镜像 → 将 `BoltZip.app` 拖入右侧 `Applications` 文件夹 → 启动后可在应用内「设置」一键开启 **访达右键一级菜单 `Bolt ›`** 与 **默认归档文件关联**。
- **网页端下载与交互演示**：也可以直接访问公网展示与下载站 [**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/)（按当前 Mac 芯片自动匹配推荐版本，附带 `SHA256SUMS.txt` 校验文件）。
- **开源未公证提示**：社区二进制包采用本地自签名分发；若首次双击出现提示，可在「系统设置 → 隐私与安全性」中点击 **仍要打开**，或对应用右键选择 **打开**。

## ✨ 核心特性

- **自动删除 `.DS_Store` 等 Mac 隐藏垃圾文件**：打包创建和解压提取时默认自动剔除 `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` 等系统元文件，发给 Windows/Linux 用户不再污染目录，Smart 解压也不受 `__MACOSX` 干扰（CLI 可用 `--keep-junk` 按需保留）。
- **访达右键一级目录 `Bolt >`**：通过原生沙盒 `FinderSync` 扩展（`BoltZipFinderSync.appex`），无需钻进「服务」子菜单，直接在访达右键最顶层一键完成：
  - 智能解压到当前位置 / 解压到同名文件夹 / 自定义解压目录 / 打开浏览 / 完整性校验
  - 一键压缩为 `ZIP` / `TAR.ZST (Zstd)` / `7z` / 多选分别打包为 ZIP / 加密与分卷高级压缩
- **Windows Zip 级包内工作台**：双击或空格调用 macOS Quick Look 直接预览包内文件，支持目录树与**嵌套压缩包层级钻取回退**、拖拽直接导出到访达、单独导出选中项为新 ZIP、归档注释查看与编辑，以及 **ZIP 包内原地增删改**（未改动条目零重压缩）。
- **JAR / APK 等包内编辑与保存**：右键条目可编辑 UTF-8／UTF-16 文本或替换文件，保存保留原后缀、条目顺序、原算法和 Store 状态；未知压缩级别使用界面说明的默认值，其他条目直接复制压缩数据。无法沿用原方式时可取消或另存为新的普通 ZIP。APK 无需配置密钥或 SDK；当前不处理签名，保存后不保证可安装或运行。
- **大文件真流式 I/O、安全符号链接与内建更新**：`>= 64 MB` 条目全链路分块流式读写（ZIP / WinZip AE-2 / ZipCrypto / TAR.*），支持 Symlink 安全保留还原与越界拦截、按实际字节报告进度的流式 `.7z` 打包、17 套分格式文件专属图标，以及应用内 GitHub Releases 更新检查（含 SHA-256 校验）。
- **液态玻璃原生体验**：
  - macOS 26+ 支持窗口半透明开关与背景不透明度精细调节（25% – 100%）；
  - 欢迎页各板块（访达提示条、功能卡片、最近列表）与侧栏摘要、底部状态栏均支持独立隐藏；
  - 窗口最小可自由缩至 `380 × 285` 迷你拖拽浮窗，低高度下自动收起次要面板只留主拖拽区。
- **自然多语言适配**：支持跟随系统语言或即时切换 **简体中文 / 繁體中文 / English / 日本語**。
- **全开源多算法内核**（静态编译 Apple Silicon `arm64` 版 `zlib`、`libzstd`、`liblzma`、`libbz2`、`liblz4`，零第三方动态库依赖，外加系统 `libarchive` 桥接 `.rar/.7z/.iso/.cab/.xar`）。
- **跨平台安全与痛点修复**：
  - **WinZip AE-2 AES-256** 双向加密（PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1）及传统 ZipCrypto 兼容；
  - **7z AES-256** 支持同时加密内容和文件名。新建 7z 并设置密码后，可用「加密文件名」隐藏包内的文件和目录列表；
  - **GB18030 / GBK / Big5 / Shift-JIS / EUC-KR** 文件名编码自动识别，告别 Windows 中文压缩包乱码；
  - 支持 `.z01 / .z02 / ... / .zip` 分卷压缩与 Smart 智能解压（单目录不套娃）。

## 🚀 快速开始

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. 运行单元测试
swift test

# 2. 编译并打包 Apple Silicon BoltZip.app（含 BoltZipFinderSync 访达扩展、CLI、App 制品包与源代码归档）
./Scripts/build_app.sh
open dist/BoltZip.app
```

### 命令行工具 (`boltzip`)

```bash
swift run -c release boltzip engines
swift run -c release boltzip bench
swift run -c release boltzip a release.zip ./src --algo zstd --aes256 --password YourPassword
swift run -c release boltzip t release.zip --password YourPassword
swift run -c release boltzip x release.zip ./out --mode smart
swift run -c release boltzip a release.7z ./src --password YourPassword --encrypt-filenames
```

## 🧩 展示页面与开发者指引

- **在线产品展示**：在 [产品展示站](https://122.51.112.183/boltzip/) 体验界面模拟器、多语言切换和算法对比。最新版制品可从上方的 GitHub Releases 下载，展示页源码位于 [showcase/](showcase/)。
- **AI Agent 与二次开发指引**：请参阅 [AGENTS.md](AGENTS.md)，了解模块划分、加密/分卷协议不变量及代码贡献规范。
- **版本更新记录**：请参阅 [CHANGELOG.md](CHANGELOG.md)。

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源。
