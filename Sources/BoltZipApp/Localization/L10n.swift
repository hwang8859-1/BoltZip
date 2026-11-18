import BoltZipCore
import Foundation

enum ResolvedLanguage: String, Sendable {
    case zhHans
    case zhHant
    case en
    case ja
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en
    case ja

    var id: String { rawValue }

    var nativePickerTitle: String {
        switch self {
        case .system: return "跟随系统 / Follow System"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    var resolved: ResolvedLanguage {
        switch self {
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        case .en: return .en
        case .ja: return .ja
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("ja") { return .ja }
            if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") || preferred.hasPrefix("zh-mo") {
                return .zhHant
            }
            if preferred.hasPrefix("zh") { return .zhHans }
            return .en
        }
    }
}

struct L10n: Sendable {
    let lang: ResolvedLanguage

    init(language: AppLanguage) {
        self.lang = language.resolved
    }

    private func t(_ sc: String, _ tc: String, _ en: String, _ ja: String) -> String {
        switch lang {
        case .zhHans: return sc
        case .zhHant: return tc
        case .en: return en
        case .ja: return ja
        }
    }


    // MARK: - Theme / Dark Mode
    var themeLabel: String { t("外观模式", "外觀模式", "Appearance", "外観モード") }
    var themeSystem: String { t("跟随系统", "跟隨系統", "System", "自動") }
    var themeLight: String { t("浅色", "淺色", "Light", "ライト") }
    var themeDark: String { t("深色", "深色", "Dark", "ダーク") }

    // MARK: - General & Welcome
    var readyStatus: String { t("就绪 · 拖入压缩包浏览，或拖入文件立即打包", "就緒 · 拖入封存檔瀏覽，或拖入檔案立即打包", "Ready — Drop an archive to browse, or files to compress", "準備完了 — 書庫をドロップして閲覧、またはファイルを圧縮") }
    var dropZoneTitle: String { t("拖放压缩包直接浏览，或拖入文件立即打包", "拖放封存檔直接瀏覽，或拖入檔案立即打包", "Drop an archive to browse, or files to compress", "書庫を開いて閲覧、またはファイルをここにドロップ") }
    var dropZoneSubtitle: String {
        if BoltPlatformCapabilities.supportsLiquidGlass {
            return t(
                "macOS 液态玻璃原生体验 · ZIP / 7z / TAR.ZST / XZ / LZ4 · 自动清理 .DS_Store 与 GBK 乱码修复",
                "macOS 液態玻璃原生體驗 · ZIP / 7z / TAR.ZST / XZ / LZ4 · 自動清除 .DS_Store 與編碼自動修正",
                "Native macOS Liquid Glass · ZIP, 7z, TAR.ZST, XZ, LZ4 · Auto-remove .DS_Store & CJK fix",
                "macOS Liquid Glass 対応 · ZIP / 7z / TAR.ZST / XZ / LZ4 · .DS_Store 自動除外＆文字コード補正"
            )
        }
        return t(
            "macOS 原生极速工作台 · ZIP / 7z / TAR.ZST / XZ / LZ4 · 自动清理 .DS_Store 与 GBK 乱码修复",
            "macOS 原生極速工作台 · ZIP / 7z / TAR.ZST / XZ / LZ4 · 自動清除 .DS_Store 與編碼自動修正",
            "Native macOS Archive Studio · ZIP, 7z, TAR.ZST, XZ, LZ4 · Auto-remove .DS_Store & CJK fix",
            "macOS ネイティブ書庫スタジオ · ZIP / 7z / TAR.ZST / XZ / LZ4 · .DS_Store 自動除外＆文字コード補正"
        )
    }

    var newArchive: String { t("新建压缩包", "新增封存檔", "New Archive", "新規圧縮") }
    var openArchive: String { t("打开压缩包", "開啟封存檔", "Open Archive", "書庫を開く") }
    var benchmark: String { t("算法跑分", "演算法跑分", "Benchmark", "ベンチマーク") }
    var showcasePage: String { t("展示页面", "產品展示頁", "Showcase", "紹介ページ") }

    // MARK: - Finder Banner
    var finderBannerEnabledTitle: String { t("访达一级右键目录「Bolt >」已启用", "Finder 第一層右鍵選單「Bolt >」已啟用", "Finder top-level menu “Bolt ›” is active", "Finder 第一階層メニュー「Bolt ›」が有効です") }
    var finderBannerDisabledTitle: String { t("将高频操作添加到访达右键一级目录「Bolt >」", "將常用功能加入 Finder 右鍵第一層選單「Bolt >」", "Add quick actions to Finder’s top-level “Bolt ›” menu", "よく使う操作を Finder 右クリック第一階層「Bolt ›」へ追加") }
    var finderBannerSubtitle: String { t("右键顶层直达：智能解压 · 解压到文件夹 · 压缩 ZIP / TAR.ZST / 7z · 加密打包", "右鍵頂層直達：智慧解壓 · 解壓至資料夾 · 壓縮 ZIP / TAR.ZST / 7z · 加密打包", "Right-click anywhere in Finder: Smart Extract, Compress ZIP / TAR.ZST / 7z & Encrypt", "右クリック最上位から即実行：スマート展開・ZIP/TAR.ZST/7z圧縮・暗号化") }
    var extensionSettings: String { t("扩展设置", "延伸功能設定", "Extensions", "拡張設定") }
    var resync: String { t("同步", "同步", "Sync", "同期") }
    var enableBoltMenu: String { t("一键启用", "一鍵啟用", "Enable", "有効にする") }
    var hideThisSection: String { t("隐藏此模块", "隱藏此區塊", "Hide section", "この項目を隠す") }

    // MARK: - Feature & Recents Cards
    var featuresTitle: String { t("Windows Zip 经典效率特性", "Windows Zip 經典效率功能", "Desktop-Class Archive Workflow", "Windows Zip 級の快適操作") }
    var featBrowseTitle: String { t("包内直览 & 全能右键", "封存檔內建瀏覽與右鍵選單", "Browse Inside & Context Actions", "展開せずに中身を閲覧＆編集") }
    var featBrowseDesc: String { t("双击/空格预览，右键直接解压、单独导出 ZIP、重命名与删改", "雙擊或空白鍵預覽，右鍵快速解壓、匯出新 ZIP、重新命名與編輯", "Double-click or press Space to Quick Look; add, rename, or delete inside ZIPs", "スペースキーでプレビュー、右クリックで直接編集や個別ZIP書き出し") }
    var featSmartTitle: String { t("智能解压 (Smart Extract)", "智慧解壓縮 (Smart Extract)", "Smart Extract", "スマート展開（二重フォルダ防止）") }
    var featSmartDesc: String { t("单目录不套娃，多文件自动归入同名子目录", "單一資料夾直接釋放，多項目自動建立同名資料夾", "Avoids nested duplicate folders automatically", "単一フォルダはそのまま、複数項目は同名フォルダを作成して展開") }
    var featMacJunkTitle: String { t("自动删除 .DS_Store 等垃圾文件", "自動清除 .DS_Store 等隱藏檔", "Auto-Remove .DS_Store & Metadata", ".DS_Store などの不要ファイルを自動除去") }
    var featMacJunkDesc: String { t("打包、包内追加与解压时自动剔除 .DS_Store、__MACOSX 与 ._*，跨平台干干净净", "壓縮、加入與解壓時自動剔除 .DS_Store、__MACOSX 與 ._*，跨平台分享更乾淨", "Automatically strips .DS_Store, __MACOSX, and ._* when packing, adding, or extracting", "圧縮・追加・展開時に .DS_Store / __MACOSX / ._* を自動除外してクリーンに共有") }
    var featEncodingTitle: String { t("Windows 中文编码自愈", "Windows 編碼亂碼自動修正", "Auto-Fix CJK Filenames", "文字化け自動補正 (GBK / Shift-JIS)") }
    var featEncodingDesc: String { t("自动识别 GB18030 / Big5 / Shift-JIS，彻底告别乱码", "自動辨識 GB18030 / Big5 / Shift-JIS，徹底告別亂碼", "Detects GB18030, Big5 & Shift-JIS archives created on Windows", "Windows 製アーカイブの日本語・中国語ファイル名を自動判別") }
    var featCryptoTitle: String { t("AE-2 AES-256 & 分卷压缩", "AE-2 AES-256 與分卷壓縮", "WinZip AE-2 & Split Volumes", "AES-256 暗号化 ＆ 分割圧縮") }
    var featCryptoDesc: String { t("支持密码跨平台互通与 .z01/.zip 分卷切分", "支援跨平台密碼互通與 .z01/.zip 分卷切分", "Standard AE-2 encryption & .z01 multi-volume archives", "WinZip/7-Zip互換暗号化と .z01 分割ボリュームに対応") }

    var recentsTitle: String { t("最近打开（右键快捷操作）", "最近開啟（右鍵快速操作）", "Recent Archives (Right-Click)", "最近の書庫（右クリック対応）") }
    var noRecents: String { t("暂无最近打开的压缩包", "尚無最近開啟的封存檔", "No recent archives yet", "最近開いた書庫はありません") }
    func itemCount(_ n: Int) -> String { t("\(n) 项", "\(n) 項", "\(n) items", "\(n) 項目") }

    // MARK: - Explorer Toolbar & Sidebar
    var backHome: String { t("首页", "首頁", "Home", "ホーム") }
    var goUp: String { t("上一级", "上一層", "Up", "上へ") }
    var newCompress: String { t("新建", "新增", "Compress", "新規圧縮") }
    var open: String { t("打开", "開啟", "Open", "開く") }
    var smartExtract: String { t("智能解压", "智慧解壓", "Smart Extract", "スマート展開") }
    var extractTo: String { t("解压到...", "解壓至...", "Extract...", "展開先を指定...") }
    var addInside: String { t("添加", "加入", "Add", "追加") }
    var newFolder: String { t("新建目录", "新增資料夾", "New Folder", "新規フォルダ") }
    var delete: String { t("删除", "刪除", "Delete", "削除") }
    var verify: String { t("校验", "驗證", "Verify", "整合性検証") }
    var layoutMenuTitle: String { t("界面与透明度", "介面與透明度", "Appearance", "表示・透過設定") }

    var folderTreeSection: String { t("目录结构", "目錄結構", "Folders", "フォルダ構成") }
    var rootLabel: String { t("根目录", "根目錄", "Root", "ルート") }
    var encryptedBadge: String { t("已加密", "已加密", "Encrypted", "暗号化") }
    var totalEntries: String { t("条目总数", "項目總數", "Entries", "総項目数") }
    var originalSize: String { t("原始大小", "原始大小", "Original", "元のサイズ") }
    var packedSize: String { t("压缩后", "壓縮後", "Packed", "圧縮後") }
    var spaceSaved: String { t("节省空间", "節省空間", "Saved", "削減率") }
    var filenameEncoding: String { t("文件名编码", "檔名編碼", "Encoding", "文字コード") }
    var searchPlaceholder: String { t("过滤归档内文件...", "搜尋封存檔內容...", "Filter archive entries...", "書庫内を検索...") }

    // MARK: - Table Columns & Drop Hint
    var colName: String { t("名称", "名稱", "Name", "名前") }
    var colOriginalSize: String { t("原始大小", "原始大小", "Size", "サイズ") }
    var colPackedSize: String { t("压缩后", "壓縮後", "Packed", "圧縮後") }
    var colRatio: String { t("压缩率", "壓縮率", "Ratio", "圧縮率") }
    var colMethod: String { t("算法 / 加密", "演算法 / 加密", "Method", "方式") }
    var colModified: String { t("修改时间", "修改時間", "Modified", "更新日時") }
    func dropToAddLabel(_ folder: String) -> String {
        t("松手即可添加到「\(folder)」", "放開即可加入「\(folder)」", "Drop to add into “\(folder)”", "ドロップして「\(folder)」へ追加")
    }
    func selectedSummary(_ count: Int, _ size: String) -> String {
        t("已选 \(count) 项 (\(size))", "已選 \(count) 項 (\(size))", "\(count) selected (\(size))", "\(count) 項目選択中 (\(size))")
    }
    var editableHint: String { t("右键支持全套操作 · 可直接拖入文件", "右鍵支援完整操作 · 可直接拖入檔案", "Right-click for actions · Drop files to add", "右クリック操作・ドラッグで直接追加可能") }

    // MARK: - Context Menus
    var ctxOpenFolder: String { t("打开文件夹", "開啟資料夾", "Open Folder", "フォルダを開く") }
    var ctxQuickLook: String { t("Quick Look 快速预览", "Quick Look 快速預覽", "Quick Look Preview", "Quick Look でプレビュー") }
    var ctxProperties: String { t("查看属性详情...", "檢視屬性詳細資訊...", "Get Info...", "詳細情報を見る...") }
    var ctxCopyName: String { t("复制文件名", "複製檔名", "Copy Name", "名前をコピー") }
    var ctxCopyPath: String { t("复制归档内路径", "複製封存檔內路徑", "Copy Archive Path", "書庫内パスをコピー") }
    var ctxExtractSelHere: String { t("智能解压选中项到所在目录", "智慧解壓選取項目至所在目錄", "Smart Extract Selected Here", "選択項目をここにスマート展開") }
    var ctxExtractSelTo: String { t("解压选中项到指定位置...", "解壓選取項目至指定位置...", "Extract Selected To...", "選択項目を指定先へ展開...") }
    var ctxExportNewZip: String { t("单独导出选中项为新 ZIP...", "單獨匯出選取項目為新 ZIP...", "Export Selected as New ZIP...", "選択項目を新規 ZIP として書き出し...") }
    var ctxVerifyArchive: String { t("校验归档完整性", "驗證封存檔完整性", "Verify Archive Integrity", "書庫の整合性を検証") }
    var ctxAddHere: String { t("在此目录添加文件...", "在此目錄加入檔案...", "Add Files Here...", "ここにファイルを追加...") }
    var ctxNewFolderHere: String { t("在此目录新建文件夹...", "在此目錄新增資料夾...", "New Folder Here...", "ここに新規フォルダ...") }
    var ctxRename: String { t("重命名...", "重新命名...", "Rename...", "名称変更...") }
    var ctxDeleteFromArchive: String { t("从归档中删除", "從封存檔中刪除", "Delete from Archive", "書庫から削除") }
    var ctxSmartExtractAll: String { t("智能解压全部", "智慧解壓全部", "Smart Extract All", "すべてスマート展開") }
    var ctxExtractAllSubfolder: String { t("全部解压到同名文件夹", "全部解壓至同名資料夾", "Extract All to Subfolder", "すべて同名フォルダへ展開") }
    var ctxExtractAllTo: String { t("解压全部到指定位置...", "解壓全部至指定位置...", "Extract All To...", "すべて指定先へ展開...") }
    var ctxVerifyAll: String { t("校验全部文件完整性", "驗證全部檔案完整性", "Verify All Entries", "全項目の整合性を検証") }
    var ctxSwitchEncoding: String { t("切换文件名编码", "切換檔名編碼", "Filename Encoding", "文字コード切り替え") }
    var ctxSortBy: String { t("排序方式", "排序方式", "Sort By", "並び替え") }
    var ctxShowInFinder: String { t("在访达中显示", "在 Finder 中顯示", "Reveal in Finder", "Finder で表示") }
    var ctxOpenDir: String { t("打开此目录", "開啟此目錄", "Open Directory", "このフォルダを開く") }
    var ctxExtractDir: String { t("解压此目录到...", "解壓此目錄至...", "Extract Directory...", "このフォルダを展開...") }
    var ctxCopyDirPath: String { t("复制目录路径", "複製目錄路徑", "Copy Directory Path", "フォルダパスをコピー") }
    var ctxAddToDir: String { t("在此目录添加文件...", "在此目錄加入檔案...", "Add Files to Directory...", "このフォルダへファイルを追加...") }
    var ctxNewSubfolder: String { t("在此目录新建子文件夹...", "在此目錄新增子資料夾...", "New Subfolder...", "サブフォルダを作成...") }
    var ctxRenameDir: String { t("重命名此目录...", "重新命名此目錄...", "Rename Directory...", "フォルダ名を変更...") }
    var ctxDeleteDir: String { t("删除此目录", "刪除此目錄", "Delete Directory", "このフォルダを削除") }
    var ctxOpenBrowse: String { t("打开浏览", "開啟瀏覽", "Open & Browse", "開いて閲覧") }
    var ctxRemoveRecent: String { t("从最近记录移除", "從最近紀錄移除", "Remove from Recents", "履歴から削除") }

    // MARK: - View / Appearance / Settings
    var appearanceTitle: String { t("界面显示与透明度", "介面顯示與透明度", "Appearance & Translucency", "外観と透過設定") }
    var languageLabel: String { t("界面语言", "介面語言", "Language", "表示言語") }
    var enableTranslucency: String { t("启用液态玻璃半透明背景", "啟用液態玻璃半透明背景", "Enable Liquid Glass translucency", "Liquid Glass 半透明背景を有効化") }
    var opacityLabel: String { t("窗口背景不透明度", "視窗背景不透明度", "Window opacity", "ウィンドウ背景の不透明度") }
    var visibleSectionsTitle: String { t("主界面模块显示开关", "主介面區塊顯示開關", "Home Screen Modules", "ホーム画面の表示項目") }
    var toggleFinderBanner: String { t("显示访达一级右键菜单提示条", "顯示 Finder 第一層右鍵提示列", "Show Finder “Bolt ›” setup banner", "Finder「Bolt ›」設定バナーを表示") }
    var toggleFeatureCard: String { t("显示功能特性介绍卡片", "顯示功能特色介紹卡片", "Show feature highlights card", "機能紹介カードを表示") }
    var toggleRecentsCard: String { t("显示最近打开归档列表", "顯示最近開啟封存檔清單", "Show recent archives card", "最近開いた書庫リストを表示") }
    var toggleSidebarInspector: String { t("显示侧栏归档摘要与编码卡", "顯示側欄封存檔摘要與編碼卡", "Show archive summary inspector", "サイドバーの概要・文字コードカードを表示") }
    var toggleStatusBar: String { t("显示底部状态栏", "顯示底部狀態列", "Show bottom status bar", "下部ステータスバーを表示") }

    var settingsTabGeneral: String { t("通用与访达集成", "一般與 Finder 整合", "General & Finder", "一般・Finder 連携") }
    var settingsTabAppearance: String { t("界面与多语言", "介面與多語言", "Appearance & Language", "外観と言語") }
    var settingsTabCodecs: String { t("开源算法内核", "開源演算法核心", "Open-Source Codecs", "オープンソースエンジン") }
    var stripMacJunkToggle: String { t("创建或解压时自动过滤 Mac 隐藏文件 (.DS_Store / __MACOSX / ._*)", "建立或解壓時自動過濾 Mac 隱藏檔 (.DS_Store / __MACOSX / ._*)", "Exclude macOS metadata (.DS_Store, __MACOSX, ._*) automatically", "Mac の不要ファイル (.DS_Store / __MACOSX / ._*) を自動除外") }
    var defaultEncodingLabel: String { t("默认文件名编码识别", "預設檔名編碼辨識", "Default filename encoding", "既定の文字コード判定") }
    var finderIntegrationSection: String { t("macOS 访达一级右键菜单 (Bolt >)", "macOS Finder 第一層右鍵選單 (Bolt >)", "macOS Finder Top-Level Menu (Bolt ›)", "macOS Finder 第一階層メニュー (Bolt ›)") }
    var finderEnabledSummary: String { t("已启用访达一级右键「Bolt >」目录", "已啟用 Finder 第一層右鍵「Bolt >」選單", "Top-level Finder menu “Bolt ›” is enabled", "Finder 第一階層メニュー「Bolt ›」は有効です") }
    var finderDisabledSummary: String { t("尚未启用访达一级右键「Bolt >」目录", "尚未啟用 Finder 第一層右鍵「Bolt >」選單", "Top-level Finder menu “Bolt ›” is not enabled", "Finder 第一階層メニュー「Bolt ›」は未設定です") }
    var reinstallOrSync: String { t("重新同步", "重新同步", "Re-sync", "再同期") }
    var installNow: String { t("一键启用", "一鍵啟用", "Enable Now", "今すぐ有効化") }
    var disableNow: String { t("停用", "停用", "Disable", "無効化") }

    var fileAssociationSection: String { t("默认压缩软件与格式关联", "預設壓縮軟體與格式關聯", "Default App & File Associations", "既定の圧縮ソフトと関連付け") }
    var fileAssociationAllDone: String { t("已将常用格式 (ZIP, 7Z, RAR, TAR, GZ, BZ2, XZ, ZST 等) 默认关联至 BoltZip", "已將常用格式 (ZIP, 7Z, RAR, TAR, GZ, BZ2, XZ, ZST 等) 預設關聯至 BoltZip", "All common formats (ZIP, 7Z, RAR, TAR, GZ, etc.) are associated with BoltZip", "常用形式は BoltZip に関連付けられています") }
    var fileAssociationPartial: String { t("部分常用格式尚未关联至 BoltZip", "部分常用格式尚未關聯至 BoltZip", "Some common formats are not associated with BoltZip", "一部の形式が未関連付けです") }
    var associateAllFormatsButton: String { t("一键关联全部常用格式", "一鍵關聯全部常用格式", "Associate All Common Formats", "すべての常用形式を一括関連付け") }
    var associateAllSuccessToast: String { t("已成功将常用压缩格式默认关联至 BoltZip！", "已成功將常用壓縮格式預設關聯至 BoltZip！", "Successfully associated common archive formats with BoltZip!", "すべての常用圧縮形式を BoltZip に関連付けました！") }

    // MARK: - Domain Enums Localized Display
    func sortColumnTitle(_ col: SortColumn) -> String {
        switch col {
        case .name: return colName
        case .uncompressedSize: return colOriginalSize
        case .compressedSize: return colPackedSize
        case .ratio: return colRatio
        case .method: return colMethod
        case .modifiedDate: return colModified
        }
    }

    func encodingTitle(_ enc: FilenameEncodingOption) -> String {
        switch enc {
        case .auto: return t("智能自动识别 (推荐)", "智慧自動辨識 (推薦)", "Auto-Detect (Recommended)", "自動判別 (推奨)")
        case .utf8: return "UTF-8 (Unicode)"
        case .gb18030: return t("简体中文 (GB18030 / GBK)", "簡體中文 (GB18030 / GBK)", "Simplified Chinese (GB18030 / GBK)", "簡体字中国語 (GB18030 / GBK)")
        case .big5: return t("繁体中文 (Big5)", "繁體中文 (Big5)", "Traditional Chinese (Big5)", "繁体字中国語 (Big5)")
        case .shiftJIS: return t("日文 (Shift-JIS)", "日文 (Shift-JIS)", "Japanese (Shift-JIS)", "日本語 (Shift-JIS)")
        case .eucKR: return t("韩文 (EUC-KR)", "韓文 (EUC-KR)", "Korean (EUC-KR)", "韓国語 (EUC-KR)")
        case .cp437: return t("DOS / 英文 (CP437)", "DOS / 英文 (CP437)", "DOS / Western (CP437)", "DOS / 欧文 (CP437)")
        }
    }

    // MARK: - Sheets & Buttons
    var cancel: String { t("取消", "取消", "Cancel", "キャンセル") }
    var confirm: String { t("确认", "確認", "Confirm", "確認") }
    var close: String { t("关闭", "關閉", "Close", "閉じる") }
    var done: String { t("完成", "完成", "Done", "完了") }
    var browse: String { t("浏览...", "瀏覽...", "Browse...", "選択...") }
    var change: String { t("更改...", "變更...", "Change...", "変更...") }
    var add: String { t("添加...", "加入...", "Add...", "追加...") }
    var startCompress: String { t("开始压缩", "開始壓縮", "Compress", "圧縮を開始") }
    var startExtract: String { t("开始解压", "開始解壓", "Extract", "展開を開始") }
    var createArchiveTitle: String { t("新建压缩归档", "新增壓縮封存檔", "Create Archive", "新規アーカイブを作成") }
    var createArchiveSub: String { t("选择开源压缩算法、加密强度与分卷策略", "選擇開源壓縮演算法、加密強度與分卷策略", "Choose open-source codec, encryption & split volumes", "オープンソース圧縮方式・暗号化・分割設定を選択") }
    var extractOptionsTitle: String { t("解压选项", "解壓縮選項", "Extract Options", "展開オプション") }
    var benchmarkTitle: String { t("开源算法本机性能跑分", "開源演算法本機效能測試", "Open-Source Codec Benchmark", "オープンソース圧縮ベンチマーク") }
    var benchmarkSub: String { t("基于 2 MB 混合结构化样本实时压测 5 大开源压缩内核", "使用 2 MB 混合樣本即時測試 5 大開源壓縮核心", "Real-time test across 5 open-source codecs (2 MB mixed payload)", "2 MB の混合データで 5 つの圧縮エンジンを実測") }
    var rerunBench: String { t("重新跑分", "重新測試", "Re-run", "再計測") }
    var runningBench: String { t("正在运行本机基准测试...", "正在執行本機基準測試...", "Running local benchmark...", "ベンチマークを実行中...") }
    var benchHardwareNote: String { t("说明：结果均为当前 Mac 硬件实际测量值", "說明：結果均為目前 Mac 硬體實測數據", "Measured live on your Mac hardware", "お使いの Mac 実機で計測された結果です") }
    var passwordPromptTitle: String { t("该压缩包已加密", "此封存檔已加密", "Archive Is Encrypted", "この書庫は暗号化されています") }
    var passwordPromptDesc: String { t("请输入解密密码（支持 WinZip AE-2 AES-256 与 ZipCrypto）", "請輸入解密密碼（支援 WinZip AE-2 AES-256 與 ZipCrypto）", "Enter password (WinZip AE-2 AES-256 & ZipCrypto supported)", "パスワードを入力してください (AE-2 AES-256 / ZipCrypto 対応)") }
    var passwordPlaceholder: String { t("输入密码", "輸入密碼", "Password", "パスワード") }
    var createFolderTitle: String { t("在归档内新建文件夹", "在封存檔內新增資料夾", "New Folder in Archive", "書庫内に新規フォルダを作成") }
    var renameEntryTitle: String { t("重命名归档条目", "重新命名封存檔項目", "Rename Archive Entry", "書庫内の項目名を変更") }
    var createBtn: String { t("创建", "建立", "Create", "作成") }
    var renameBtn: String { t("重命名", "重新命名", "Rename", "変更") }

    // MARK: - Create & Extract Form Labels
    var outputTargetSection: String { t("输出目标", "輸出目標", "Output", "出力先") }
    var archiveNameField: String { t("归档名称（不含扩展名）", "封存檔名稱（不含副檔名）", "Archive Name", "書庫名（拡張子なし）") }
    var saveLocationLabel: String { t("保存位置", "儲存位置", "Location", "保存先") }
    var inputItemsLabel: String { t("待压缩项目", "待壓縮項目", "Items", "対象項目") }
    var formatAlgoSection: String { t("格式与开源算法", "格式與開源演算法", "Format & Open-Source Codec", "形式と圧縮エンジン") }
    var archiveFormatLabel: String { t("归档格式", "封存格式", "Format", "形式") }
    var compressionAlgoLabel: String { t("压缩算法", "壓縮演算法", "Algorithm", "圧縮方式") }
    var compressionPresetLabel: String { t("压缩级别预设", "壓縮等級預設", "Preset", "圧縮プリセット") }
    var fineLevelLabel: String { t("算法精细级别", "演算法精細等級", "Compression Level", "圧縮レベル") }
    var encryptionSection: String { t("加密保护 (WinZip 兼容)", "加密保護 (WinZip 相容)", "Encryption (WinZip Compatible)", "暗号化保護 (WinZip 互換)") }
    var encryptionMethodLabel: String { t("加密方式", "加密方式", "Encryption", "暗号化方式") }
    var confirmPasswordField: String { t("确认密码", "確認密碼", "Confirm Password", "パスワード確認") }
    var passwordMismatch: String { t("两次输入的密码不一致", "兩次輸入的密碼不一致", "Passwords do not match", "パスワードが一致しません") }
    var advancedOptionsSection: String { t("高级选项与跨平台兼容", "進階選項與跨平台相容", "Advanced & Compatibility", "詳細・互換オプション") }
    var splitVolumeLabel: String { t("分卷大小", "分卷大小", "Split Volumes", "分割サイズ") }
    var customSplitMBField: String { t("单卷体积 (MB)", "單卷大小 (MB)", "Volume Size (MB)", "分割サイズ (MB)") }
    var willGeneratePrefix: String { t("将生成：", "將產生：", "Output: ", "作成ファイル：") }

    var destFolderLabel: String { t("目标文件夹", "目標資料夾", "Destination", "展開先フォルダ") }
    var extractModeLabel: String { t("解压模式", "解壓模式", "Extract Mode", "展開モード") }
    var overwriteLabel: String { t("遇到重名文件", "遇到同名檔案", "If File Exists", "同名ファイルの扱い") }
    var decryptPasswordSection: String { t("解密密码", "解密密碼", "Password", "パスワード") }
    var compressSpeedCol: String { t("压缩速度", "壓縮速度", "Compress", "圧縮速度") }
    var decompressSpeedCol: String { t("解压速度", "解壓速度", "Decompress", "展開速度") }


    // MARK: - Slogan & About
    var slogan: String {
        t(
            "快如闪电，通透如玻 —— 让 macOS 压缩像桌面本身一样顺手",
            "快如閃電，通透如玻 —— 讓 macOS 壓縮像桌面本身一樣順手",
            "Lightning-fast archives. Liquid-clear macOS craft.",
            "稲妻の速さ、ガラスの透明感 —— macOS のための書庫スタジオ"
        )
    }
    var aboutMenuTitle: String { t("关于 BoltZip", "關於 BoltZip", "About BoltZip", "BoltZip について") }
    var aboutVersionLabel: String { BoltPlatformCapabilities.runtimeVersionSummary(appVersion: "0.9.0") }
    var aboutDesc: String {
        t(
            "开源压缩/解压缩工作台，原生融合 Windows Zip 效率交互、访达一级 Bolt 菜单与液态玻璃设计。",
            "開源壓縮/解壓縮工作台，原生融合 Windows Zip 效率操作、Finder 第一層 Bolt 選單與液態玻璃設計。",
            "An open-source macOS archive studio combining Windows-Zip workflows, top-level Finder actions, and Liquid Glass craft.",
            "Windows Zip 級の快適操作、Finder 第一階層 Bolt メニュー、Liquid Glass デザインを融合したオープンソース圧縮ツール。"
        )
    }
    var openGitHub: String { t("访问 GitHub 仓库", "前往 GitHub 專案", "GitHub Repository", "GitHub リポジトリ") }
    var openSourceEnginesLine: String { "zlib · Zstandard · XZ / LZMA2 · bzip2 · LZ4 · libarchive" }
    var copyrightLine: String { "MIT License · © 2026 BoltZip Contributors" }

    var alertTitle: String { t("BoltZip 提示", "BoltZip 提示", "BoltZip", "BoltZip") }

    // MARK: - Quick Task Floating HUD
    func hudCompressingTitle(_ fmt: String) -> String {
        t("正在压缩为 \(fmt)", "正在壓縮為 \(fmt)", "Compressing to \(fmt)", "\(fmt) に圧縮中")
    }
    var hudSmartExtractingTitle: String { t("正在智能解压", "正在智慧解壓", "Smart Extracting", "スマート展開中") }
    var hudExtractingSubfolderTitle: String { t("正在解压到同名文件夹", "正在解壓至同名資料夾", "Extracting to Folder", "フォルダへ展開中") }
    var hudPausedTitle: String { t("已暂停", "已暫停", "Paused", "一時停止中") }
    var hudCompletedTitle: String { t("处理完成", "處理完成", "Completed", "完了") }
    var hudCancelledTitle: String { t("已停止", "已停止", "Stopped", "停止しました") }
    var hudFailedTitle: String { t("操作失败", "操作失敗", "Failed", "エラー") }
    var hudPreparing: String { t("正在扫描文件...", "正在掃描檔案...", "Preparing files...", "ファイルを準備中...") }
    var hudCalculatingETA: String { t("正在计算剩余时间...", "正在計算剩餘時間...", "Calculating remaining time...", "残り時間を計算中...") }
    var hudAlmostDone: String { t("即将完成", "即將完成", "Almost done", "まもなく完了") }
    func hudRemaining(_ formatted: String) -> String {
        t("剩余约 \(formatted)", "剩餘約 \(formatted)", "About \(formatted) left", "残り約 \(formatted)")
    }
    func hudElapsed(_ formatted: String) -> String {
        t("耗时 \(formatted)", "耗時 \(formatted)", "Finished in \(formatted)", "所要時間 \(formatted)")
    }
    func hudQueuedBadge(_ count: Int) -> String {
        t("+\(count) 排队中", "+\(count) 排隊中", "+\(count) queued", "+\(count) 待機中")
    }
    var hudPauseBtn: String { t("暂停", "暫停", "Pause", "一時停止") }
    var hudResumeBtn: String { t("继续", "繼續", "Resume", "再開") }
    var hudStopBtn: String { t("停止", "停止", "Stop", "停止") }
    var hudRevealBtn: String { t("在访达中显示", "在 Finder 中顯示", "Show in Finder", "Finder で表示") }
    var hudUnlockBtn: String { t("解锁继续", "解鎖繼續", "Unlock", "解除して続行") }
    var hudNeedsPassword: String { t("压缩包已加密，请输入密码继续解压", "封存檔已加密，請輸入密碼繼續解壓", "Archive is encrypted. Enter password to continue.", "暗号化されています。パスワードを入力してください。") }
}
