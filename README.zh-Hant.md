<div align="center">

# BoltZip ⚡

**快如閃電，通透如玻 —— 讓 macOS 壓縮像桌面本身一樣順手**

[简体中文](README.md) | **繁體中文** | [English](README.en.md) | [日本語](README.ja.md)

![macOS 12.0+](https://img.shields.io/badge/macOS-12.0%E2%80%9326%20(Universal)-0ea5e9?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6.0-6366f1?style=flat-square)
![Release v0.9.3](https://img.shields.io/badge/release-v0.9.3-facc15?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

</div>

---

**BoltZip v0.9.3** 是面向 **macOS 12 Monterey ~ macOS 26+（Universal：`arm64` + Intel `x86_64`）** 的長期相容性發佈版本（新功能主線 `main` 自 `v1.0.0` 起專注 Apple Silicon 與 macOS 26+）。它將 Windows 經典封存工具（7-Zip / WinZip / Bandizip）的高效操作邏輯融入 macOS 原生體驗（於 macOS 26+ 啟用 **Liquid Glass 液態玻璃**，macOS 12–15 自動停用玻璃效果並提供乾淨的原生介面），徹底告別雙擊就將檔案全數釋放一地的困擾。

## ✨ 核心功能

- **自動刪除 `.DS_Store` 等 Mac 隱藏垃圾檔**：壓縮建立、ZIP 封存檔原地新增檔案以及解壓縮時預設自動剔除 `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` 等系統中繼檔，傳送給 Windows/Linux 使用者不污染目錄，智慧解壓也不受 `__MACOSX` 干擾。
- **Finder 右鍵第一層選單 `Bolt >`**：透過原生沙盒 `FinderSync` 延伸功能（`BoltZipFinderSync.appex`），無需進入「服務」子選單，直接在右鍵最頂層一鍵執行：
  - 智慧解壓縮 / 解壓至同名資料夾 / 開啟瀏覽 / 完整性驗證
  - 一鍵壓縮為 `ZIP` / `TAR.ZST (Zstd)` / `7z` / 加密與分卷進階壓縮
- **Windows Zip 級封存檔工作台**：雙擊或按下空白鍵即可呼叫 macOS Quick Look 預覽內部檔案，無需整包解壓；支援樹狀瀏覽、即時搜尋排序、檢視 CRC32 屬性、單獨匯出選取項目為新 ZIP，以及 **ZIP 封存檔原地新增、重新命名與刪除**（未變動項目零重新壓縮）。
- **液態玻璃與舊版原生適配**：
  - macOS 26+ 提供視窗半透明開關與背景不透明度微調（25% – 100%）；macOS 12–15 自動停用玻璃效果並回退為乾淨原生控制項；
  - 首頁各區塊（Finder 提示列、特色介紹卡、最近開啟清單）及側欄摘要、狀態列皆可獨立隱藏；
  - 視窗最小可縮放至 `380 × 285` 迷你拖放視窗，高度較小時自動僅保留主拖放區。
- **自然多國語言支援**：支援依系統語言自動切換，亦可於設定中即時切換 **简体中文 / 繁體中文 / English / 日本語**。
- **全開源通用壓縮引擎核心**（靜態連結 Universal `arm64 + x86_64` 版 `zlib`、`libzstd`、`liblzma`、`libbz2`、`liblz4` 與 `libarchive`，無外部動態函式庫相依，支援 `.rar/.7z/.iso/.cab/.xar`）。
- **跨平台相容與安全防護**：
  - 支援 **WinZip AE-2 AES-256** 雙向加密（PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1）及傳統 ZipCrypto；
  - 自動辨識 **GB18030 / GBK / Big5 / Shift-JIS / EUC-KR** 檔名編碼，解決 Windows 封存檔亂碼問題；
  - 支援 `.z01 / .z02 / ... / .zip` 分卷壓縮與 Smart 智慧解壓縮。

## 🚀 快速開始

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. 執行單元測試
swift test

# 2. 編譯並封裝 BoltZip.app（含 Finder 延伸功能、CLI 與發佈壓縮包）
./Scripts/build_app.sh
open dist/BoltZip.app
```

### 命令列工具 (`boltzip`)

```bash
swift run -c release boltzip engines
swift run -c release boltzip bench
swift run -c release boltzip a release.zip ./src --algo zstd --aes256 --password YourPassword
swift run -c release boltzip t release.zip --password YourPassword
swift run -c release boltzip x release.zip ./out --mode smart
```

## 🧩 展示頁面與開發者文件

- **線上產品展示與下載頁**：造訪公開展示網站 [**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/)，即可體驗互動式模擬器與演算法效能比較，並直接下載 `BoltZip v0.9.3 Universal` 安裝包與原始碼歸檔（原始檔案位於 [showcase/](showcase/)）。
- **AI Agent 與開發指南**：請參閱 [AGENTS.md](AGENTS.md)。
- **版本更新紀錄**：請參閱 [CHANGELOG.md](CHANGELOG.md)。

## 📄 授權條款

本專案採用 [MIT License](LICENSE) 授權。
