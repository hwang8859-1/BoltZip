<div align="center">

<img src="showcase/app-icon.png" width="112" height="112" alt="BoltZip" />

# BoltZip ⚡

**快如閃電，通透如玻 —— 讓 macOS 壓縮像桌面本身一樣順手**

[简体中文](README.md) | **繁體中文** | [English](README.en.md) | [日本語](README.ja.md)

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B%20(Apple%20Silicon)-0ea5e9?style=flat-square)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-6366f1?style=flat-square)
[![Release v1.0.3](https://img.shields.io/badge/release-v1.0.3-facc15?style=flat-square)](https://github.com/hwang8859-1/BoltZip/releases/latest)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

<p>
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.dmg"><strong>⬇️ 直接下載最新版 v1.0.3 (.dmg · Apple Silicon)</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg">🛡 下載相容版 v0.9.3 (.dmg · Intel / macOS 12–26)</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/latest">📦 GitHub Releases</a>
  &nbsp;·&nbsp;
  <a href="https://122.51.112.183/boltzip/">🌐 線上展示與下載站</a>
</p>

</div>

---

**BoltZip** 是一款專為 **macOS 26.0+（Apple Silicon M 系列 `arm64` 專屬最佳化）** 打造的開源壓縮與解壓縮工作台。它將 Windows 經典封存工具（7-Zip / WinZip / Bandizip）的高效操作邏輯融入 macOS 26 原生 **Liquid Glass 液態玻璃** 體驗，徹底告別雙擊就將檔案全數釋放一地的困擾。

> 💡 **Intel Mac 或 macOS 12–15 使用者**：長期相容版本 **v0.9.3 Universal (`arm64 + x86_64`)** 維護於 [`legacy/macos-12`](../../tree/legacy/macos-12) 分支與 [`v0.9.3`](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) 標籤。

> [!IMPORTANT]
> **目前活躍開發分支：[GitHub 預設 `dev-*` 分支](../../)** · `main` 分支僅供穩定版發佈使用且已受保護。提交程式碼或 PR 請務必保持指向目前預設開發分支，詳見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## ⬇️ 快速下載與安裝

| 適用機型與系統 | 推薦版本 | 直接下載連結 | 發佈頁面 |
| :--- | :--- | :--- | :--- |
| **Apple Silicon (M 系列 `arm64`) · macOS 26.0+** | **`v1.0.3`**（最新正式版） | [下載 `.dmg` 安裝映像檔](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.dmg) · [可攜包 `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.zip) | [Release v1.0.3 ↗](https://github.com/hwang8859-1/BoltZip/releases/latest) |
| **Intel (`x86_64`) 或 macOS 12.0–15 / 26+** | **`v0.9.3`**（Universal 全相容版） | [下載 `.dmg` 相容映像檔](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg) · [可攜包 `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.zip) | [Release v0.9.3 ↗](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) |

- **安裝步驟**：打開下載的 `.dmg` 映像檔 → 將 `BoltZip.app` 拖入右側 `Applications` 資料夾 → 啟動後可在「設定」一鍵啟用 **Finder 右鍵第一層選單 `Bolt ›`** 與 **預設檔案關聯**。
- **線上展示與下載站**：亦可造訪 [**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/)（依 Mac 平台自動推薦對應版本，附帶 `SHA256SUMS.txt` 校驗清單）。
- **開源未公證提示**：社群發行版採本機自簽署封裝；若首次開啟受系統安全提示阻擋，可前往「系統設定 → 隱私權與安全性」點選 **強制打開**，或於應用程式上按右鍵選擇 **打開**。

## ✨ 核心功能

- **自動刪除 `.DS_Store` 等 Mac 隱藏垃圾檔**：壓縮建立、ZIP 封存檔原地新增檔案以及解壓縮時預設自動剔除 `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` 等系統中繼檔，傳送給 Windows/Linux 使用者不污染目錄，智慧解壓也不受 `__MACOSX` 干擾。
- **Finder 右鍵第一層選單 `Bolt >`**：透過原生沙盒 `FinderSync` 延伸功能（`BoltZipFinderSync.appex`），無需進入「服務」子選單，直接在右鍵最頂層一鍵執行：
  - 智慧解壓縮 / 解壓至同名資料夾 / 解壓到指定目錄 / 開啟瀏覽 / 完整性驗證
  - 一鍵壓縮為 `ZIP` / `TAR.ZST (Zstd)` / `7z` / 多選個別打包為 ZIP / 加密與分卷進階壓縮
- **Windows Zip 級封存檔工作台**：雙擊或按下空白鍵即可呼叫 macOS Quick Look 預覽內部檔案，支援樹狀瀏覽與**巢狀壓縮檔層級返回**、拖曳直接匯出至 Finder、單獨匯出為新 ZIP、封存檔註解檢視與編輯，以及 **ZIP 封存檔原地新增、重新命名與刪除**（未變動項目零重新壓縮）。
- **大檔分塊串流、安全符號連結與內建更新**：`>= 64 MB` 項目支援全流程分塊串流讀寫（ZIP / WinZip AE-2 / ZipCrypto / TAR.*）、符號連結安全保留還原與越界防範、依實際位元組回報進度的串流 `.7z` 封裝、17 組分格式專屬圖示，以及應用內 GitHub Releases 檢查更新（含 SHA-256 校驗）。
- **液態玻璃原生體驗**：
  - macOS 26+ 提供視窗半透明開關與背景不透明度微調（25% – 100%）；
  - 首頁各區塊（Finder 提示列、特色介紹卡、最近開啟清單）及側欄摘要、狀態列皆可獨立隱藏；
  - 視窗最小可縮放至 `380 × 285` 迷你拖放視窗，高度較小時自動僅保留主拖放區。
- **自然多國語言支援**：支援依系統語言自動切換，亦可於設定中即時切換 **简体中文 / 繁體中文 / English / 日本語**。
- **全開源 Apple Silicon 壓縮核心**（靜態連結 `arm64` 版 `zlib`、`libzstd`、`liblzma`、`libbz2`、`liblz4`，無外部動態函式庫相依，並透過系統 `libarchive` 支援 `.rar/.7z/.iso/.cab/.xar`）。
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

- **線上產品展示**：在 [產品展示站](https://122.51.112.183/boltzip/) 體驗介面模擬器、多語言切換和演算法比較。最新版可從上方的 GitHub Releases 下載，展示頁原始碼位於 [showcase/](showcase/)。
- **AI Agent 與開發指南**：請參閱 [AGENTS.md](AGENTS.md)。
- **版本更新紀錄**：請參閱 [CHANGELOG.md](CHANGELOG.md)。

## 📄 授權條款

本專案採用 [MIT License](LICENSE) 授權。
