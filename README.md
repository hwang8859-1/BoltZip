# BoltZip ⚡

专为 **macOS 27.3**（Apple Silicon 原生）打造的高颜值开源压缩/解压缩工作台。将 Windows 版 Zip 软件（7-Zip / WinZip / Bandizip）最顺手的效率交互完整带入 macOS。

## 核心特性

- **Windows Zip 级档案工作台**：双击打开压缩包直接浏览树形目录、排序检索、Space/双击调起原生 Quick Look 预览单文件，无需全量解压。
- **ZIP 包内原地增删改**：直接向打开的 ZIP 中拖入新文件、新建文件夹、重命名或删除条目，未改动条目零重压缩。
- **全开源多算法内核**（静态编译于 `CBoltCompression`，零第三方动态库运行时依赖）：
  - **DEFLATE** (`zlib`) — 通用标准 `.zip` / `.gz`
  - **Zstandard** (`libzstd`) — 现代高比超高速 `.tar.zst` / ZIP Method 93
  - **LZMA2 / XZ** (`liblzma`) — 极限压缩比 `.tar.xz` / `.xz`
  - **bzip2** (`libbz2`) — 经典块排序 `.tar.bz2` / ZIP Method 12
  - **LZ4** (`liblz4`) — 实时高速流 `.tar.lz4` / `.lz4`
  - **7z / ISO / CAB / XAR** — 基于 macOS `libarchive` 桥接支持
- **WinZip AE-2 AES-256 双向加密**：PBKDF2-HMAC-SHA1 + AES-256-CTR + 10 字节 HMAC-SHA1 校验标签，并兼容传统 ZipCrypto 解密/加密。
- **Windows ↔ macOS 跨平台痛点解决**：
  - **智能文件名编码纠偏**：自动识别未标注 UTF-8 的 Windows `GB18030 / GBK`、`Big5`、`Shift-JIS`、`EUC-KR` 压缩包，彻底告别乱码。
  - **Mac 隐藏垃圾过滤**：默认过滤 `.DS_Store`、`__MACOSX` 与 `._*` 资源分叉。
  - **智能解压 (Smart Extract)**：单一根目录直接释放，多根目录自动建同名子目录。
  - **分卷压缩 & 完整性校验**：支持 `.z01 / .z02 / ... / .zip` 分卷切分与逐条目 CRC32 / HMAC 校验报告。
- **访达右键集成 & CLI**：内置一键安装 Finder Quick Actions（`~/Library/Services`），并提供原生 `boltzip` 命令行工具。
- **交互式产品展示页**：见 `showcase/index.html`。

## 目录结构

```text
BoltZip/
├── Package.swift                 # Swift 6 + macOS 27.2+ 工程定义
├── Sources/
│   ├── CBoltCompression/         # 开源 C 编解码统一桥接层 (zlib/zstd/lzma/bz2/lz4)
│   ├── BoltZipCore/              # 纯 Swift 归档引擎 (ZIP64/AE-2/Split/TAR/PAX/GBK/7z)
│   ├── BoltZipCLI/               # 终端命令 boltzip
│   └── BoltZipApp/               # SwiftUI + AppKit 原生桌面应用
├── Tests/BoltZipCoreTests/       # 核心编解码、加密、分卷、编码与互操作测试
├── Scripts/
│   ├── build_app.sh              # 构建自包含 BoltZip.app 安装包与图标
│   └── generate_icon.swift       # 生成 macOS AppIcon.icns
└── showcase/                     # 独立交互式网页展示页
```

## 构建与运行

```bash
# 1. 运行完整单元测试
swift test

# 2. 构建独立自包含 BoltZip.app（含 CLI 与展示页）
./Scripts/build_app.sh
open dist/BoltZip.app

# 3. 命令行工具示例
swift run -c release boltzip engines
swift run -c release boltzip bench
swift run -c release boltzip a release.zip ./MyFolder --aes256 --password Secret
```
