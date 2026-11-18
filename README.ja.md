<div align="center">

# BoltZip ⚡

**稲妻の速さ、ガラスの透明感 —— macOS のためのオープンソース書庫スタジオ**

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | **日本語**

![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B%20(Apple%20Silicon)-0ea5e9?style=flat-square)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-6366f1?style=flat-square)
![Release v1.0.0](https://img.shields.io/badge/release-v1.0.0-facc15?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-34d399?style=flat-square)

</div>

---

**BoltZip** は **Apple Silicon（M シリーズ `arm64`）& macOS 26.0+ 専用** に最適化されたオープンソースの圧縮・展開ツールです。7-Zip / WinZip / Bandizip など Windows 定番圧縮ソフトの軽快な操作性とネイティブの **Liquid Glass** を融合しました。

> 💡 **Intel Mac や macOS 12〜15 をお使いの方**：長期互換リリース **v0.9.1 Universal (`arm64 + x86_64`)** を [`legacy/macos-12`](../../tree/legacy/macos-12) ブランチおよび `v0.9.1` タグにて提供しています。

> [!IMPORTANT]
> **現在の開発ブランチ：`dev-1.0.1`**（デフォルトブランチ）· `main` は保護されたリリース専用ブランチです。PR は必ず **`dev-1.0.1`** をターゲットに作成してください（詳細は [CONTRIBUTING.md](CONTRIBUTING.md)）。

## ✨ 主な特長

- **`.DS_Store` など Mac 不要ファイルを自動削除・除外**：新規圧縮・ZIP 内への追加・展開のすべてで `.DS_Store`、`__MACOSX`、`._*`、`.Spotlight-V100`、`.Trashes` を既定で自動除外。Windows/Linux ユーザーへの共有時にゴミを残さず、スマート展開も妨げません（CLI の `--keep-junk` または設定で保持も可能）。
- **Finder 右クリック第一階層メニュー「Bolt ›」**：サンドボックス対応 `FinderSync` 拡張（`BoltZipFinderSync.appex`）により、「サービス」サブメニューに埋もれることなく右クリック最上位から即実行できます：
  - スマート展開 / 同名フォルダへ展開 / BoltZip で開く / 整合性検証
  - ワンクリックで `ZIP` / `TAR.ZST (Zstd)` / `7z` 圧縮、暗号化・分割圧縮ウィザード
- **展開不要の閲覧 ＆ ZIP 内直接編集**：ダブルクリックまたは `Space` キーで macOS Quick Look プレビューを起動。フォルダ階層移動、検索・ソート、CRC32 詳細表示、選択項目のみの新規 ZIP 書き出し、さらに **ZIP 内の追加・名称変更・削除**（未変更ファイルは再圧縮なし）に対応。
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

- **オンライン紹介・ダウンロードページ**：公開サイト [**https://122.51.112.183/boltzip/**](https://122.51.112.183/boltzip/) にて UI シミュレーター、圧縮エンジン比較、および `BoltZip v1.0.0 Apple Silicon` とソースコードアーカイブのダウンロードをご確認いただけます（ソースは [showcase/](showcase/) に同梱）。
- **AI Agent / コントリビューターガイド**：[AGENTS.md](AGENTS.md) をご覧ください。
- **変更履歴**：[CHANGELOG.md](CHANGELOG.md) をご覧ください。

## 📄 ライセンス

[MIT License](LICENSE) の下で公開されています。
