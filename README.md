<div align="center">

# BoltZip ⚡

**快如闪电，通透如玻 —— 让 macOS 压缩像桌面本身一样顺手**

**简体中文** | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md)

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B%20(Universal)-0ea5e9?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6.0-6366f1?style=flat-square)
![Release v0.9.0](https://img.shields.io/badge/release-v0.9.0-facc15?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

</div>

---

**BoltZip** 是一款专为 **macOS 14.0+（Universal：Apple Silicon `arm64` + Intel `x86_64`）** 打造的开源压缩与解压缩工作台。它融合了 Windows 经典压缩工具（7-Zip / WinZip / Bandizip）的高效交互与 macOS 原生体验（macOS 26+ 启用 **Liquid Glass 液态玻璃**，macOS 14–15 自动禁用玻璃效果并回退为原生纯色卡片），告别双击即全量解压一地的传统体验。

## ✨ 核心特性

- **自动删除 `.DS_Store` 等 Mac 隐藏垃圾文件**：打包创建、ZIP 包内追加文件以及解压提取时默认自动剔除 `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` 等系统元文件，发给 Windows/Linux 用户不再污染目录，Smart 解压也不受 `__MACOSX` 干扰（CLI 可用 `--keep-junk` 按需保留）。
- **访达右键一级目录 `Bolt >`**：通过原生沙盒 `FinderSync` 扩展（`BoltZipFinderSync.appex`），无需钻进「服务」子菜单，直接在访达右键最顶层一键完成：
  - 智能解压到当前位置 / 解压到同名文件夹 / 打开浏览 / 完整性校验
  - 一键压缩为 `ZIP` / `TAR.ZST (Zstd)` / `7z` / 加密与分卷高级压缩
- **Windows Zip 级包内工作台**：双击或空格调用 macOS Quick Look 直接预览包内文件，无需解压全包；支持目录树浏览、搜索排序、查看 CRC32 属性、单独导出选中项为新 ZIP，以及 **ZIP 包内原地增删改**（未改动条目零重压缩）。
- **液态玻璃 & 旧版原生适配**：
  - macOS 26+ 支持窗口半透明开关与背景不透明度精细调节（25% – 100%）；macOS 14–15 自动禁用玻璃效果并回退原生界面；
  - 欢迎页各板块（访达提示条、功能卡片、最近列表）与侧栏摘要、底部状态栏均支持独立隐藏；
  - 窗口最小可自由缩至 `380 × 285` 迷你拖拽浮窗，低高度下自动收起次要面板只留主拖拽区。
- **自然多语言适配**：支持跟随系统语言或即时切换 **简体中文 / 繁體中文 / English / 日本語**。
- **全开源多算法内核**（静态编译 Universal `arm64 + x86_64` 版 `zlib`、`libzstd`、`liblzma`、`libbz2`、`liblz4`，零第三方动态库依赖，外加系统 `libarchive` 桥接 `.7z/.iso/.cab/.xar`）。
- **跨平台安全与痛点修复**：
  - **WinZip AE-2 AES-256** 双向加密（PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1）及传统 ZipCrypto 兼容；
  - **GB18030 / GBK / Big5 / Shift-JIS / EUC-KR** 文件名编码自动识别，告别 Windows 中文压缩包乱码；
  - 支持 `.z01 / .z02 / ... / .zip` 分卷压缩与 Smart 智能解压（单目录不套娃）。

## 🚀 快速开始

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. 运行单元测试
swift test

# 2. 编译并打包 Universal BoltZip.app（含 BoltZipFinderSync 访达扩展、CLI、App 制品包与源代码归档）
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
```

## 🧩 展示页面与开发者指引

- **交互式产品展示页**：直接用浏览器打开 [showcase/index.html](showcase/index.html)，即可体验浏览器端交互模拟器、多语言切换与算法对比面板。
- **AI Agent 与二次开发指引**：请参阅 [AGENTS.md](AGENTS.md)，了解模块划分、加密/分卷协议不变量及代码贡献规范。
- **版本更新记录**：请参阅 [CHANGELOG.md](CHANGELOG.md)。

## 📄 开源协议

本项目基于 [MIT License](LICENSE) 开源。
