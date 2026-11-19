<div align="center">

<img src="showcase/app-icon.png" width="112" height="112" alt="BoltZip" />

# BoltZip ⚡

**稲妻の速さ、ガラスの透明感 —— macOS のためのオープンソース書庫スタジオ**

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | **日本語**

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B%20(Apple%20Silicon)-0ea5e9?style=flat-square)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-6366f1?style=flat-square)
[![Release v1.0.3](https://img.shields.io/badge/release-v1.0.3-facc15?style=flat-square)](https://github.com/hwang8859-1/BoltZip/releases/latest)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

<p>
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.dmg"><strong>⬇️ 最新版 v1.0.3 をダウンロード (.dmg · Apple Silicon)</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg">🛡 互換版 v0.9.3 (.dmg · Intel / macOS 12–26)</a>
  &nbsp;·&nbsp;
  <a href="https://github.com/hwang8859-1/BoltZip/releases/latest">📦 GitHub Releases</a>
  &nbsp;·&nbsp;
  <a href="https://122.51.112.183/boltzip/">🌐 オンライン配布ページ</a>
</p>

</div>

---

**BoltZip** は **Apple Silicon（M シリーズ `arm64`）& macOS 26.0+ 専用** に最適化されたオープンソースの圧縮・展開ツールです。7-Zip / WinZip / Bandizip など Windows 定番圧縮ソフトの軽快な操作性とネイティブの **Liquid Glass** を融合しました。

> 💡 **Intel Mac や macOS 12〜15 をお使いの方**：長期互換リリース **v0.9.3 Universal (`arm64 + x86_64`)** を [`legacy/macos-12`](../../tree/legacy/macos-12) ブランチおよび [`v0.9.3`](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) タグにて提供しています。

> [!IMPORTANT]
> **現在の開発ブランチ：[GitHub デフォルトの `dev-*` ブランチ](../../)** · `main` は保護されたリリース専用ブランチです。PR は必ず現在のデフォルト開発ブランチをターゲットに作成してください（詳細は [CONTRIBUTING.md](CONTRIBUTING.md)）。

## ⬇️ クイックダウンロード ＆ インストール

| 対象 Mac / macOS | 推奨バージョン | 直接ダウンロード | リリースページ |
| :--- | :--- | :--- | :--- |
| **Apple Silicon (`arm64`) · macOS 26.0+** | **`v1.0.3`**（最新安定版） | [`.dmg` インストーラー](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.dmg) · [ポータブル `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v1.0.3/BoltZip-1.0.3-macOS-arm64.zip) | [Release v1.0.3 ↗](https://github.com/hwang8859-1/BoltZip/releases/latest) |
| **Intel (`x86_64`) または macOS 12.0–15 / 26+** | **`v0.9.3`**（Universal 互換版） | [`.dmg` インストーラー](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.dmg) · [ポータブル `.zip`](https://github.com/hwang8859-1/BoltZip/releases/download/v0.9.3/BoltZip-0.9.3-macOS-universal.zip) | [Release v0.9.3 ↗](https://github.com/hwang8859-1/BoltZip/releases/tag/v0.9.3) |

- **導入手順**：ダウンロードした `.dmg` を開く → `BoltZip.app` を `Applications` へドラッグ → 起動後、設定画面から **Finder 右クリック「Bolt ›」メニュー** と **既定の関連付け** をワンクリックで有効化できます。
- **Web 配布ページ**：[**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/) でもお使いの Mac に合わせた推奨トラック案内と `SHA256SUMS.txt` をご確認いただけます。
- **初回起動時の補足**：オープンソース配布版はアドホック署名のため、初回起動時に警告が出た場合は `BoltZip.app` を右クリック → **開く**（または「システム設定 → プライバシーとセキュリティ → **このまま開く**」）を選択してください。

## ✨ 主な特長

- **`.DS_Store` など Mac 不要ファイルを自動削除・除外**：新規圧縮・ZIP 内への追加・展開のすべてで `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` を既定で自動除外。Windows/Linux ユーザーへの共有時にゴミを残さず、スマート展開も妨げません（CLI の `--keep-junk` または設定で保持も可能）。
- **Finder 右クリック第一階層メニュー「Bolt ›」**：サンドボックス対応 `FinderSync` 拡張（`BoltZipFinderSync.appex`）により、「サービス」サブメニューに埋もれることなく右クリック最上位から即実行できます：
  - スマート展開 / 同名フォルダへ展開 / 指定フォルダへ展開 / BoltZip で開く / 整合性検証
  - ワンクリックで `ZIP` / `TAR.ZST (Zstd)` / `7z` / 複数選択の個別 ZIP 圧縮 / 暗号化・分割圧縮ウィザード
- **展開不要の閲覧・Finder ドラッグ書き出し・ZIP 内直接編集**：ダブルクリックまたは `Space` キーで Quick Look 起動、**入れ子書庫の階層ドリルダウンと戻るナビゲーション**、Finder への直接ドラッグ出力（`NSFilePromiseProvider`）、書庫コメントの表示・編集、さらに **ZIP 内の追加・名称変更・削除**（未変更項目は再圧縮なし）に対応。
- **チャンク真ストリーミング I/O・安全シンボリックリンク・アプリ内更新**：`64 MB` 以上の項目を ZIP / WinZip AE-2 / ZipCrypto / TAR.* で低メモリ逐次処理。パストラバーサル対策付きシンボリックリンク保持・復元、APFS ハードリンクによる高速 `.7z` ステージング、17 種の拡張子別アイコン、GitHub Releases 自動更新チェック（SHA-256 検証付き）を搭載。
- **ネイティブ Liquid Glass 体験**：
  - macOS 26+ では半透明効果と背景不透明度（25% – 100%）を調整可能；
  - ホーム画面の各カード（Finder 案内バナー・機能紹介・履歴リスト）やサイドバー概要・ステータスバーを個別に非表示化；
  - 最小 `380 × 285` のコンパクトなドロップウィンドウまで自由に縮小でき、狭い高さではメイン領域のみをスッキリ表示します。
- **自然な 4 言語対応**：macOS のシステム言語へ自動追従するほか、設定から **简体中文 / 繁體中文 / English / 日本語** を即時切り替え可能。
- **純オープンソース Apple Silicon 圧縮コア**：`arm64` 向けの `zlib`・`libzstd`・`liblzma`・`libbz2`・`liblz4` を静的リンク（外部ランタイムライブラリ不要）し、システム `libarchive` 経由で `.rar` / `.7z` / `.iso` / `.cab` / `.xar` にも対応。
- **クロスプラットフォーム互換性**：
  - **WinZip AE-2 AES-256** 暗号化（`PBKDF2-HMAC-SHA1` + `AES-256-CTR` + 10B `HMAC-SHA1`）および ZipCrypto 互換；
  - Windows 環境で作成された `Shift-JIS` / `GB18030 (GBK)` / `Big5` / `EUC-KR` ファイル名の文字化け自動補正；
  - `.z01/.z02/.../.zip` 分割ボリュームおよび二重フォルダを防ぐスマート展開に対応。

## 🚀 クイックスタート

```bash
git clone https://github.com/hwang8859-1/BoltZip.git
cd BoltZip

# 1. ユニットテストの実行
swift test

# 2. BoltZip.app のビルド（Finder 拡張・CLI・配布用 ZIP を生成）
./Scripts/build_app.sh
open dist/BoltZip.app
```

### CLI コマンド (`boltzip`)

```bash
swift run -c release boltzip engines
swift run -c release boltzip bench
swift run -c release boltzip a release.zip ./src --algo zstd --aes256 --password YourPassword
swift run -c release boltzip t release.zip --password YourPassword
swift run -c release boltzip x release.zip ./out --mode smart
```

## 🧩 紹介ページ ＆ 開発者向けドキュメント

- **オンライン紹介**：[製品紹介サイト](https://122.51.112.183/boltzip/) で UI シミュレーター、言語切り替え、圧縮エンジンの比較をお試しいただけます。最新版は上記の GitHub Releases から入手できます。サイトのソースコードは [showcase/](showcase/) にあります。
- **AI Agent / コントリビューターガイド**：[AGENTS.md](AGENTS.md) をご覧ください。
- **変更履歴**：[CHANGELOG.md](CHANGELOG.md) をご覧ください。

## 📄 ライセンス

[MIT License](LICENSE) の下で公開されています。
