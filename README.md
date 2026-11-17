# BoltZip ⚡

专为 **macOS 27.3**（Apple Silicon 原生）打造的开源压缩/解压缩工作台。将 Windows 版 Zip 软件（7-Zip / WinZip / Bandizip）最顺手的效率交互与 macOS 原生 **Liquid Glass（液态玻璃）** 融为一体。

## 核心特性

- **访达右键一级目录 `Bolt >`**：通过原生沙盒 `FinderSync` 扩展 (`BoltZipFinderSync.appex`) 将高频压缩/解压动作直接显示在访达右键最顶层菜单。
- **Windows Zip 级档案工作台**：包内树形浏览、搜索排序、Quick Look 预览、ZIP 原地增删改（零重压缩）、右键属性详情与单独导出为新 ZIP。
- **液态玻璃 & 模块化主界面**：
  - 支持窗口半透明开关与背景不透明度精细滑动调节；
  - 欢迎页各板块（访达菜单横幅、功能介绍卡、最近打开列表）与侧栏摘要/状态栏均支持独立隐藏与恢复。
- **自然多语言适配**：支持跟随系统语言或手动切换 **简体中文 / 繁體中文 / English / 日本語**。
- **全开源多算法内核**（静态编译 `zlib`、`libzstd`、`liblzma`、`libbz2`、`liblz4`，零第三方动态库依赖，外加 `libarchive` 桥接 `.7z/.iso/.cab/.xar`）。
- **安全与跨平台兼容**：WinZip AE-2 AES-256 双向加密、传统 ZipCrypto、分卷压缩（`.z01/.zip`）、GB18030/Big5/Shift-JIS 文件名自动纠偏、Mac 隐藏文件过滤与 Smart 智能解压。

## 开发者与 AI Agent 指引

如果你准备基于本项目继续二次开发，请参阅根目录下的 [AGENTS.md](AGENTS.md)，了解模块职责、静态链接说明与关键协议约束。

## 克隆、构建与测试

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. 运行全套单元测试
swift test

# 2. 构建并签名自包含 BoltZip.app（含 BoltZipFinderSync 访达扩展与展示页）
./Scripts/build_app.sh
open dist/BoltZip.app

# 3. 命令行工具示例
swift run -c release boltzip engines
swift run -c release boltzip bench
```

## 产品展示页面

打开 [showcase/index.html](showcase/index.html) 即可在浏览器体验支持多语言切换的交互式界面模拟器与算法对比面板。
