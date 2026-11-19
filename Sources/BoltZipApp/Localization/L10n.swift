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
    var dropZoneTitle: String { t("拖入压缩包浏览，或拖入文件打包", "拖入封存檔瀏覽，或拖入檔案壓縮", "Drop an archive to browse, or files to compress", "書庫をドラッグして閲覧、ファイルをドラッグして圧縮") }

    var newArchive: String { t("新建压缩包", "新增封存檔", "New Archive", "新規圧縮") }
    var openArchive: String { t("打开压缩包", "開啟封存檔", "Open Archive", "書庫を開く") }
    var benchmark: String { t("算法跑分", "演算法跑分", "Benchmark", "ベンチマーク") }
    var showcasePage: String { t("展示页面", "產品展示頁", "Showcase", "紹介ページ") }

    // MARK: - Finder Banner
    var finderBannerEnabledTitle: String { t("访达快捷菜单已启用", "Finder 快捷選單已啟用", "Finder quick actions are enabled", "Finder クイック操作は有効です") }
    var finderBannerDisabledTitle: String { t("启用访达快捷菜单", "啟用 Finder 快捷選單", "Enable Finder quick actions", "Finder クイック操作を有効にする") }
    var extensionSettings: String { t("扩展设置", "延伸功能設定", "Extensions", "拡張設定") }
    var resync: String { t("同步", "同步", "Sync", "同期") }
    var enableBoltMenu: String { t("一键启用", "一鍵啟用", "Enable", "有効にする") }
    var hideThisSection: String { t("隐藏此模块", "隱藏此區塊", "Hide section", "この項目を隠す") }

    // MARK: - Feature & Recents Cards
    var featuresTitle: String { t("功能特性", "功能特色", "Features", "機能") }
    var featFormatsTitle: String { t("多格式支持", "支援多種格式", "Multiple archive formats", "さまざまな書庫形式") }
    var featFormatsDesc: String { t("支持 ZIP、RAR、7z、TAR.ZST、XZ 和 LZ4 等格式。", "支援 ZIP、RAR、7z、TAR.ZST、XZ 和 LZ4 等格式。", "Supports ZIP, RAR, 7z, TAR.ZST, XZ, LZ4, and more.", "ZIP、RAR、7z、TAR.ZST、XZ、LZ4 などに対応。") }
    var featBrowseTitle: String { t("包内浏览与编辑", "在封存檔內瀏覽與編輯", "Browse and edit archives", "書庫の閲覧と編集") }
    var featBrowseDesc: String { t("用快速查看预览文件，直接编辑 ZIP。", "使用快速查看預覽檔案，直接編輯 ZIP。", "Preview files with Quick Look and edit ZIPs in place.", "クイックルックでプレビューし、ZIP を直接編集。") }
    var featSmartTitle: String { t("智能解压", "智慧解壓縮", "Smart extract", "スマート展開") }
    var featSmartDesc: String { t("保留单个根目录，多项内容归入同名文件夹。", "保留單一根目錄，多個項目歸入同名資料夾。", "Keeps a single root folder and groups multiple items.", "単一フォルダはそのまま、複数項目は同名フォルダに展開。") }
    var featMacJunkTitle: String { t("清理系统文件", "清除系統檔案", "Clean up metadata", "不要なメタデータを除外") }
    var featMacJunkDesc: String { t("自动排除 .DS_Store 和 __MACOSX 等文件。", "自動排除 .DS_Store 和 __MACOSX 等檔案。", "Automatically excludes .DS_Store, __MACOSX, and similar files.", ".DS_Store や __MACOSX などを自動で除外。") }
    var featEncodingTitle: String { t("自动识别文件名编码", "自動辨識檔名編碼", "Detect filename encodings", "ファイル名の文字コードを自動判別") }
    var featEncodingDesc: String { t("识别 GB18030、Big5 和 Shift-JIS 等编码。", "辨識 GB18030、Big5 和 Shift-JIS 等編碼。", "Detects GB18030, Big5, Shift-JIS, and more.", "GB18030、Big5、Shift-JIS などに対応。") }
    var featCryptoTitle: String { t("加密与分卷", "加密與分卷", "Encryption and split volumes", "暗号化と分割圧縮") }
    var featCryptoDesc: String { t("支持 AES-256 加密和 .z01/.zip 分卷。", "支援 AES-256 加密和 .z01/.zip 分卷。", "Supports AES-256 encryption and .z01/.zip volumes.", "AES-256 暗号化と .z01/.zip の分割に対応。") }

    var featGlassTitle: String { t("液态玻璃", "液態玻璃", "Liquid Glass", "Liquid Glass") }
    var featGlassDesc: String { t("原生界面，可调整窗口通透度。", "原生介面，可調整視窗通透度。", "Native controls with adjustable window translucency.", "ウインドウの透過度を調整できるネイティブ UI。") }

    var recentsTitle: String { t("最近打开", "最近開啟", "Recent archives", "最近開いた書庫") }
    var noRecents: String { t("暂无最近打开的压缩包", "尚無最近開啟的封存檔", "No recent archives yet", "最近開いた書庫はありません") }
    func itemCount(_ n: Int) -> String { t("\(n) 项", "\(n) 項", "\(n) items", "\(n) 項目") }

    // MARK: - Explorer Toolbar & Sidebar
    var backHome: String { t("首页", "首頁", "Home", "ホーム") }
    var backToArchiveRoot: String { t("返回根目录", "返回根目錄", "Archive Root", "ルートへ戻る") }
    var goUp: String { t("上一级", "上一層", "Up", "上へ") }
    var goDown: String { t("下一级（返回上次目录）", "下一層（返回上次目錄）", "Next Level", "次の階層へ") }
    var newCompress: String { t("新建", "新增", "Compress", "新規圧縮") }
    var open: String { t("打开", "開啟", "Open", "開く") }
    var smartExtract: String { t("智能解压", "智慧解壓", "Smart Extract", "スマート展開") }
    var smartExtractShortcutHint: String { t("智能解压 (⌘E)", "智慧解壓 (⌘E)", "Smart Extract (⌘E)", "スマート展開 (⌘E)") }
    var extractTo: String { t("解压到...", "解壓至...", "Extract...", "展開先を指定...") }
    var addInside: String { t("添加", "加入", "Add", "追加") }
    var newFolder: String { t("新建目录", "新增資料夾", "New Folder", "新規フォルダ") }
    var delete: String { t("删除", "刪除", "Delete", "削除") }
    var verify: String { t("校验", "驗證", "Verify", "整合性検証") }
    var inspectorButton: String { t("显示/隐藏简介 (⌘I)", "顯示/隱藏簡介 (⌘I)", "Toggle Inspector (⌘I)", "インスペクタ表示切替 (⌘I)") }
    var layoutMenuTitle: String { t("界面与透明度", "介面與透明度", "Appearance", "表示・透過設定") }

    var folderTreeSection: String { t("目录结构", "目錄結構", "Folders", "フォルダ構成") }
    var rootLabel: String { t("根目录", "根目錄", "Root", "ルート") }
    var encryptedBadge: String { t("已加密", "已加密", "Encrypted", "暗号化") }
    var unencryptedLabel: String { t("未加密", "未加密", "Unencrypted", "暗号化なし") }
    var totalEntries: String { t("条目总数", "項目總數", "Entries", "総項目数") }
    var originalSize: String { t("原始大小", "原始大小", "Original", "元のサイズ") }
    var packedSize: String { t("压缩后", "壓縮後", "Packed", "圧縮後") }
    var spaceSaved: String { t("节省空间", "節省空間", "Saved", "削減率") }
    var filenameEncoding: String { t("文件名编码", "檔名編碼", "Encoding", "文字コード") }
    var selectedItemTitle: String { t("选中条目", "選取項目", "Selected Item", "選択中の項目") }
    func selectedMultiTitle(_ count: Int) -> String {
        t("已选 \(count) 项", "已選 \(count) 項", "\(count) Selected", "\(count) 項目選択中")
    }
    var inspectorFolderType: String { t("文件夹", "資料夾", "Folder", "フォルダ") }
    var inspectorGenericFile: String { t("文件", "檔案", "File", "ファイル") }
    func inspectorFileExt(_ ext: String) -> String {
        t("\(ext) 文件", "\(ext) 檔案", "\(ext) File", "\(ext) ファイル")
    }
    var quickLookShort: String { t("预览", "預覽", "Quick Look", "プレビュー") }
    var extractSelectedShort: String { t("解压选中项", "解壓選取項目", "Extract Selected", "選択を展開") }
    var moreDetailsShort: String { t("详情…", "詳細資訊…", "Details…", "詳細…") }
    var searchPlaceholder: String { t("搜索目录...", "搜尋目錄...", "Search...", "検索...") }

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
    var ctxJumpToPath: String { t("跳转到当前文件路径", "跳轉至檔案所在路徑", "Reveal in Archive Path", "このファイルのパスへ移動") }
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
    var appearanceTitle: String { t("外观与语言", "外觀與語言", "Appearance & Language", "外観と言語") }
    var languageLabel: String { t("界面语言", "介面語言", "Language", "表示言語") }
    func languageCompactTitle(_ language: AppLanguage) -> String {
        language == .system ? themeSystem : language.nativePickerTitle
    }
    var backgroundColorLabel: String { t("背景色调", "背景色調", "Background Tint", "背景カラー") }
    var bgColorPureWhite: String { t("纯净白", "純淨白", "Pure White", "ピュアホワイト") }
    var bgColorIceBlue: String { t("冰川蓝", "冰川藍", "Glacier Blue", "グレイシャーブルー") }
    var bgColorLavender: String { t("淡雅紫", "淡雅紫", "Lavender", "ラベンダー") }
    var bgColorMint: String { t("薄荷绿", "薄荷綠", "Mint", "ミント") }
    var bgColorWarmCream: String { t("暖柔杏", "暖柔杏", "Warm Cream", "ウォームクリーム") }
    var bgColorCustom: String { t("自定义", "自訂", "Custom", "カスタム") }
    var enableTranslucency: String { t("液态玻璃半透明", "液態玻璃半透明", "Liquid Glass Translucency", "Liquid Glass 半透明") }
    var appIconStyleLabel: String { t("应用图标样式", "App 圖示樣式", "App Icon Style", "アプリアイコン") }
    var appIconStyleHint: String {
        t(
            "运行时金光掠过闪电。退出后，固定在程序坞的图标保留配色和金色尾部。",
            "執行時金光掠過閃電。結束 App 後，固定在 Dock 的圖示保留配色與金色尾部。",
            "Gold sweeps across the bolt while running. A pinned Dock icon keeps its color and gold tip after quitting.",
            "起動中は金色の光が稲妻を流れます。Dock に追加したアイコンは、終了後も選んだ色と金色の先端を保ちます。"
        )
    }
    var glassIntensityLabel: String { t("玻璃通透度", "玻璃通透度", "Glass Intensity", "ガラス透過強度") }
    var glassSoftLabel: String { t("柔和", "柔和", "Soft", "控えめ") }
    var glassStrongLabel: String { t("极强", "極強", "Intense", "最大") }
    var opacityLabel: String { t("窗口背景不透明度", "視窗背景不透明度", "Window opacity", "ウィンドウ背景の不透明度") }
    var visibleSectionsTitle: String { t("主界面模块", "主介面區塊", "Workspace Modules", "画面表示モジュール") }
    var toggleFinderBanner: String { t("访达菜单引导条", "Finder 選單引導列", "Finder Setup Banner", "Finder 設定バナー") }
    var toggleFeatureCard: String { t("功能特性卡片", "功能特色卡片", "Feature Highlights", "機能紹介カード") }
    var toggleRecentsCard: String { t("最近打开列表", "最近開啟清單", "Recent Archives", "最近の書庫リスト") }
    var toggleSidebarInspector: String { t("侧栏简介与编码", "側欄摘要與編碼", "Sidebar Inspector", "サイドバー概要") }
    var toggleStatusBar: String { t("底部状态栏", "底部狀態列", "Bottom Status Bar", "ステータスバー") }

    var settingsTabGeneral: String { t("通用", "一般", "General", "一般") }
    var settingsTabAppearance: String { t("外观", "外觀", "Appearance", "外観") }
    var settingsTabCodecs: String { t("性能与内核", "效能與核心", "Performance", "性能・エンジン") }
    var settingsGeneralArchiveSection: String { t("压缩与解压", "壓縮與解壓", "Archives", "圧縮・展開") }
    var stripMacJunkToggle: String { t("创建或解压时自动过滤 Mac 隐藏文件 (.DS_Store / __MACOSX / ._*)", "建立或解壓時自動過濾 Mac 隱藏檔 (.DS_Store / __MACOSX / ._*)", "Exclude macOS metadata (.DS_Store, __MACOSX, ._*) automatically", "Mac の不要ファイル (.DS_Store / __MACOSX / ._*) を自動除外") }
    var stripMacJunkTitle: String { t("过滤 Mac 隐藏文件", "過濾 Mac 隱藏檔", "Strip Mac Metadata", "Mac 不要ファイルを除外") }
    var stripMacJunkSubtitle: String { t("自动剔除 .DS_Store、__MACOSX 与 ._*", "自動剔除 .DS_Store、__MACOSX 與 ._*", "Auto-exclude .DS_Store, __MACOSX & ._*", ".DS_Store / __MACOSX / ._* を自動除外") }
    var defaultEncodingLabel: String { t("默认文件名编码", "預設檔名編碼", "Default Encoding", "既定の文字コード") }
    var finderIntegrationSection: String { t("访达右键菜单", "Finder 右鍵選單", "Finder Context Menu", "Finder 右クリックメニュー") }
    var settingsFinderSubtitle: String { t("右键文件或文件夹直接快速压解", "右鍵檔案或資料夾即可直接壓解", "Compress or extract files directly from the context menu", "右クリックからファイルやフォルダを即座に圧縮・展開") }
    var statusEnabledBadge: String { t("已启用", "已啟用", "Enabled", "有効") }
    var statusDisabledBadge: String { t("未启用", "未啟用", "Disabled", "無効") }
    var finderRowTitle: String { t("访达一级菜单「Bolt ›」", "Finder 第一層選單「Bolt ›」", "Finder “Bolt ›” Menu", "Finder「Bolt ›」メニュー") }
    var finderEnabledSummary: String { t("已启用访达一级右键「Bolt >」目录", "已啟用 Finder 第一層右鍵「Bolt >」目錄", "Top-level Finder “Bolt ›” menu is enabled", "Finder 最上位メニュー「Bolt ›」が有効です") }
    var finderDisabledSummary: String { t("尚未启用访达一级右键「Bolt >」目录", "尚未啟用 Finder 第一層右鍵「Bolt >」目錄", "Top-level Finder “Bolt ›” menu is disabled", "Finder 最上位メニュー「Bolt ›」は無効です") }
    var reinstallOrSync: String { t("重新同步", "重新同步", "Re-sync", "再同期") }
    var installNow: String { t("一键启用", "一鍵啟用", "Enable", "有効化") }
    var disableNow: String { t("停用", "停用", "Disable", "無効化") }

    // MARK: - Default File Associations & Multi-Core Engine
    var defaultAssociationsSection: String { t("默认文件关联", "預設檔案關聯", "File Associations", "ファイル関連付け") }
    var defaultAssociationsSubtitle: String { t("将 BoltZip 设为双击压缩文件时的系统默认打开应用", "將 BoltZip 設為雙擊壓縮檔時的系統預設開啟程式", "Set BoltZip as the system default app for opening archives", "アーカイブを開く際の既定アプリとして BoltZip を設定します") }
    func defaultAssociationsSummary(_ active: Int, _ total: Int) -> String {
        t("已接管 \(active) / \(total) 类常见格式", "已接管 \(active) / \(total) 類常見格式", "\(active) / \(total) common groups active", "\(active) / \(total) 種類の形式を担当中")
    }
    var defaultAssociationsTitle: String { t("系统默认关联", "系統預設關聯", "Default Handler", "既定の関連付け") }
    var setAllDefaultsBtn: String { t("全部设为默认", "全部設為預設", "Set All Default", "すべて既定に") }
    var restoreSystemDefaultsBtn: String { t("恢复系统默认", "恢復系統預設", "Restore Defaults", "既定に戻す") }
    var defaultAppUpdatedSuccess: String { t("默认文件关联已更新", "預設檔案關聯已更新", "Default file associations updated", "ファイルの関連付けを更新しました") }
    var alreadyDefaultBadge: String { "BoltZip" }

    func associationGroupTitle(_ group: ArchiveAssociationGroup) -> String {
        switch group {
        case .zip: return t("ZIP 归档", "ZIP 封存檔", "ZIP Archives", "ZIP 書庫")
        case .rar: return t("RAR 归档", "RAR 封存檔", "RAR Archives", "RAR 書庫")
        case .sevenZip: return t("7-Zip 归档", "7-Zip 封存檔", "7-Zip Archives", "7-Zip 書庫")
        case .tar: return t("TAR 组合归档", "TAR 組合封存檔", "TAR Archives", "TAR アーカイブ")
        case .singleStreams: return t("单文件压缩流", "單檔壓縮串流", "Compressed Streams", "単一圧縮ストリーム")
        case .cabXar: return t("CAB 与 XAR", "CAB 與 XAR", "CAB & XAR", "CAB / XAR")
        case .iso: return t("ISO 光盘镜像", "ISO 光碟映像", "ISO Disk Images", "ISO ディスクイメージ")
        }
    }

    var multiCoreTitle: String { t("多核并行加速", "多核心並行加速", "Multi-Core Acceleration", "マルチコア高速化") }
    var multiCoreSubtitle: String { t("支持多文件 ZIP 并行编解码与 Zstd / XZ 多线程流式压缩", "支援多檔案 ZIP 平行編解碼與 Zstd / XZ 多執行緒串流壓縮", "Parallel multi-file ZIP codecs & multi-threaded Zstd / XZ compression", "複数ファイル ZIP の並列処理と Zstd / XZ マルチスレッド圧縮に対応") }
    func multiCoreBadge(_ cores: Int) -> String {
        t("已启用 · \(cores) 核并行", "已啟用 · \(cores) 核心平行", "Active · \(cores) Cores", "有効 · \(cores) コア並列")
    }
    var multiCoreCountLabel: String { t("并行核心数", "並行核心數", "Worker Cores", "使用コア数") }
    var multiCoreBenefitSubtitle: String {
        t(
            "加速批量 ZIP 与 Zstd / XZ 压解，降核更省电",
            "加速批量 ZIP 與 Zstd / XZ 壓解，降核更省電",
            "Speeds up ZIP & Zstd/XZ; lower saves power",
            "ZIP・Zstd/XZ を高速化（少コアで省電力）"
        )
    }
    var settingsCodecsSection: String { t("开源算法内核", "開源演算法核心", "Open-Source Codecs", "オープンソースエンジン") }

    func encodingCompactTitle(_ enc: FilenameEncodingOption) -> String {
        switch enc {
        case .auto: return t("自动识别", "自動辨識", "Auto", "自動判別")
        case .utf8: return "UTF-8"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        case .shiftJIS: return "Shift-JIS"
        case .eucKR: return "EUC-KR"
        case .cp437: return "CP437"
        }
    }

    func multiCoreMenuAuto(_ workers: Int) -> String {
        t(
            "自动调度（推荐 · \(workers) 核）",
            "自動排程（推薦 · \(workers) 核心）",
            "Auto Schedule (Recommended · \(workers) \(workers == 1 ? "Core" : "Cores"))",
            "自動割り当て（推奨 · \(workers) コア）"
        )
    }
    func multiCoreMenuCoreOption(_ cores: Int, total: Int) -> String {
        if cores == 1 {
            return t("1 核（单核省电静音）", "1 核心（單核省電安靜）", "1 Core (Quiet & Power-Saving)", "1 コア（省電力・静音）")
        }
        if cores == total {
            return t("\(cores) 核（全部核心）", "\(cores) 核心（全部核心）", "\(cores) Cores (All Cores)", "\(cores) コア（全コア）")
        }
        return multiCoreCoresUnit(cores)
    }
    func multiCorePickerAuto(_ workers: Int) -> String {
        t("自动 (\(workers) 核)", "自動 (\(workers) 核心)", "Auto (\(workers) \(workers == 1 ? "Core" : "Cores"))", "自動 (\(workers) コア)")
    }
    func multiCorePickerCoreOption(_ cores: Int, total: Int) -> String {
        if cores == 1 {
            return t("1 核 · 省电", "1 核心 · 省電", "1 Core · Quiet", "1 コア · 省電力")
        }
        if cores == total {
            return t("\(cores) 核 · 全部", "\(cores) 核心 · 全部", "\(cores) Cores · Max", "\(cores) コア · 最大")
        }
        return multiCoreCoresUnit(cores)
    }
    func multiCoreBadgeAuto(_ workers: Int) -> String {
        t("自动 · \(workers) 核", "自動 · \(workers) 核心", "Auto · \(workers) \(workers == 1 ? "Core" : "Cores")", "自動 · \(workers) コア")
    }
    func multiCoreBadgeManual(_ cores: Int) -> String {
        t("手动 · \(cores) 核", "手動 · \(cores) 核心", "Manual · \(cores) \(cores == 1 ? "Core" : "Cores")", "手動 · \(cores) コア")
    }
    func multiCoreCoresUnit(_ cores: Int) -> String {
        t("\(cores) 核", "\(cores) 核心", "\(cores) \(cores == 1 ? "Core" : "Cores")", "\(cores) コア")
    }
    func multiCoreFollowGlobal(_ summary: String) -> String {
        t("跟随设置 (\(summary))", "跟隨設定 (\(summary))", "Use Settings (\(summary))", "設定に従う (\(summary))")
    }

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
    var createArchiveSub: String { t("配置格式、算法、加密与分卷选项", "設定格式、演算法、加密與分卷選項", "Configure format, codec, encryption & split volumes", "形式・圧縮方式・暗号化・分割設定を構成") }
    var createChooseBtn: String { t("选择", "選擇", "Browse", "選択") }
    var createAddBtn: String { t("添加", "加入", "Add", "追加") }
    var extractOptionsTitle: String { t("解压选项", "解壓縮選項", "Extract Options", "展開オプション") }
    var benchmarkTitle: String { t("开源算法本机性能跑分", "開源演算法本機效能測試", "Open-Source Codec Benchmark", "オープンソース圧縮ベンチマーク") }
    var benchmarkSub: String { t("基于 2 MB 混合结构化样本实时压测 5 大开源压缩内核", "使用 2 MB 混合樣本即時測試 5 大開源壓縮核心", "Real-time test across 5 open-source codecs (2 MB mixed payload)", "2 MB の混合データで 5 つの圧縮エンジンを実測") }
    var rerunBench: String { t("重新跑分", "重新測試", "Re-run", "再計測") }
    var runningBench: String { t("正在运行本机基准测试...", "正在執行本機基準測試...", "Running local benchmark...", "ベンチマークを実行中...") }
    var benchHardwareNote: String { t("说明：结果均为当前 Mac 硬件实际测量值", "說明：結果均為目前 Mac 硬體實測數據", "Measured live on your Mac hardware", "お使いの Mac 実機で計測された結果です") }
    var passwordPromptTitle: String { t("该压缩包已加密", "此封存檔已加密", "Archive Is Encrypted", "この書庫は暗号化されています") }
    var passwordPromptDesc: String { t("请输入解密密码（支持 AE-2 AES-256、ZipCrypto 与 RAR / 7z）", "請輸入解密密碼（支援 AE-2 AES-256、ZipCrypto 與 RAR / 7z）", "Enter password (AE-2 AES-256, ZipCrypto, RAR & 7z supported)", "パスワードを入力してください (AES-256 / ZipCrypto / RAR / 7z 対応)") }
    var passwordPlaceholder: String { t("输入密码", "輸入密碼", "Password", "パスワード") }
    var createFolderTitle: String { t("在归档内新建文件夹", "在封存檔內新增資料夾", "New Folder in Archive", "書庫内に新規フォルダを作成") }
    var renameEntryTitle: String { t("重命名归档条目", "重新命名封存檔項目", "Rename Archive Entry", "書庫内の項目名を変更") }
    var createBtn: String { t("创建", "建立", "Create", "作成") }
    var renameBtn: String { t("重命名", "重新命名", "Rename", "変更") }

    // MARK: - Create & Extract Form Labels
    var outputTargetSection: String { t("输出目标", "輸出目標", "Output", "出力先") }
    var archiveNameField: String { t("归档名称", "封存檔名稱", "Archive Name", "書庫名") }
    var saveLocationLabel: String { t("保存位置", "儲存位置", "Location", "保存先") }
    var inputItemsLabel: String { t("待压缩项目", "待壓縮項目", "Items", "対象項目") }
    var formatAlgoSection: String { t("格式与算法", "格式與演算法", "Format & Codec", "形式と圧縮方式") }
    var archiveFormatLabel: String { t("归档格式", "封存格式", "Format", "形式") }
    var compressionAlgoLabel: String { t("压缩算法", "壓縮演算法", "Algorithm", "圧縮方式") }
    var compressionPresetLabel: String { t("压缩预设", "壓縮預設", "Preset", "圧縮プリセット") }
    var fineLevelLabel: String { t("精细级别", "精細等級", "Level", "圧縮レベル") }
    var encryptionSection: String { t("加密保护", "加密保護", "Encryption", "暗号化") }
    var encryptionMethodLabel: String { t("加密方式", "加密方式", "Encryption", "暗号化方式") }
    var confirmPasswordField: String { t("确认密码", "確認密碼", "Confirm", "パスワード確認") }
    var passwordMismatch: String { t("两次输入的密码不一致", "兩次輸入的密碼不一致", "Passwords do not match", "パスワードが一致しません") }
    var advancedOptionsSection: String { t("高级选项", "進階選項", "Advanced", "詳細オプション") }
    var splitVolumeLabel: String { t("分卷切分", "分卷切分", "Split Volumes", "分割サイズ") }
    var splitPresetNone: String { t("不分卷", "不分卷", "Single", "分割しない") }
    var splitPreset10MB: String { t("10 MB · 聊天软件友好", "10 MB · 通訊軟體適用", "10 MB · Messaging", "10 MB · チャット向け") }
    var splitPresetCustom: String { t("自定义 (MB)", "自訂 (MB)", "Custom (MB)", "カスタム (MB)") }
    var customSplitMBField: String { t("单卷上限", "單卷上限", "Volume Limit", "分割上限") }
    var customSplitShortTitle: String { t("自定义", "自訂", "Custom", "カスタム") }
    var willGeneratePrefix: String { t("输出：", "輸出：", "Output: ", "作成：") }

    func encryptionCompactTitle(_ method: EncryptionMethod) -> String {
        switch method {
        case .none: return t("不加密", "不加密", "None", "なし")
        case .aes256: return "AES-256"
        case .zipCrypto: return "ZipCrypto"
        }
    }

    func createFollowGlobalWorkers(_ summary: String) -> String {
        t("全局 (\(summary))", "全域 (\(summary))", "Default (\(summary))", "標準 (\(summary))")
    }

    func createPresetShortTitle(_ preset: CompressionPreset) -> String {
        switch preset {
        case .store: return t("存储", "儲存", "Store", "無圧縮")
        case .fastest: return t("极速", "極速", "Fastest", "最速")
        case .balanced: return t("均衡", "均衡", "Balanced", "標準")
        case .maximum: return t("高压缩", "高壓縮", "Max", "高圧縮")
        case .ultra: return t("极限", "極限", "Ultra", "最高")
        }
    }

    var destFolderLabel: String { t("目标文件夹", "目標資料夾", "Destination", "展開先フォルダ") }
    var extractModeLabel: String { t("解压模式", "解壓模式", "Extract Mode", "展開モード") }
    var overwriteLabel: String { t("遇到重名文件", "遇到同名檔案", "If File Exists", "同名ファイルの扱い") }
    var decryptPasswordSection: String { t("解密密码", "解密密碼", "Password", "パスワード") }
    var compressSpeedCol: String { t("压缩速度", "壓縮速度", "Compress", "圧縮速度") }
    var decompressSpeedCol: String { t("解压速度", "解壓速度", "Decompress", "展開速度") }


    // MARK: - Slogan & About
    var slogan: String {
        t(
            "快如闪电，通透如玻",
            "快如閃電，通透如玻",
            "Lightning-fast. Liquid-clear.",
            "稲妻の速さ、ガラスの透明感"
        )
    }
    var aboutMenuTitle: String { t("关于 BoltZip", "關於 BoltZip", "About BoltZip", "BoltZip について") }
    var aboutVersionLabel: String { BoltPlatformCapabilities.runtimeVersionSummary(appVersion: BoltZipVersion.current) }
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

    // MARK: - macOS Menu Bar
    var fileMenuTitle: String { t("文件", "檔案", "File", "ファイル") }
    var helpMenuTitle: String { t("帮助", "輔助說明", "Help", "ヘルプ") }
    var settingsMenuTitle: String { t("设置…", "設定…", "Settings…", "設定…") }
    var quitMenuTitle: String { t("退出 BoltZip", "結束 BoltZip", "Quit BoltZip", "BoltZip を終了") }
    var closeWindowMenuTitle: String { t("关闭窗口", "關閉視窗", "Close Window", "ウインドウを閉じる") }

    static let allAboutMenuTitles: Set<String> = [
        "关于 BoltZip", "關於 BoltZip", "About BoltZip", "BoltZip について"
    ]
    static let allFileMenuTitles: Set<String> = [
        "文件", "檔案", "File", "ファイル"
    ]
    static let allHelpMenuTitles: Set<String> = [
        "帮助", "輔助說明", "Help", "ヘルプ"
    ]

    static func normalizedMenuTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "\u{200B}", with: "")
    }

    var alertTitle: String { t("BoltZip 提示", "BoltZip 提示", "BoltZip", "BoltZip") }

    // MARK: - Extract Conflict Prompt
    var extractConflictTitle: String {
        t("发现同名文件或文件夹", "發現同名檔案或資料夾", "Conflicting Files or Folders", "同名の項目が既に存在します")
    }
    func extractConflictMessage(folder: String, names: [String]) -> String {
        let preview = names.prefix(2).joined(separator: "、")
        let suffix: String
        if names.count > 2 {
            suffix = t(" 等 \(names.count) 项", " 等 \(names.count) 項", " (and \(names.count - 2) more)", " ほか \(names.count) 件")
        } else {
            suffix = ""
        }
        let targetName = preview + suffix
        return t(
            "目标路径「\(folder)」下已存在「\(targetName)」，是否覆盖？",
            "目標路徑「\(folder)」下已存在「\(targetName)」，是否覆蓋？",
            "“\(targetName)” already exists in “\(folder)”. Do you want to overwrite it?",
            "「\(folder)」内に「\(targetName)」が既に存在します。上書きしますか？"
        )
    }
    var overwriteExistingBtn: String { t("覆盖", "覆蓋", "Overwrite", "上書き") }
    var keepBothRenameBtn: String { t("自动重命名保留两者", "自動重新命名保留兩者", "Keep Both", "両方とも残す") }
    func batchArchivesTitle(_ count: Int) -> String {
        t("\(count) 个压缩包", "\(count) 個封存檔", "\(count) Archives", "\(count) 件の書庫")
    }
    func batchExtractConflictMessage(archives: [(archiveName: String, conflictingNames: [String])]) -> String {
        let previewLines = archives.prefix(3).map { item -> String in
            let names = item.conflictingNames.prefix(2).joined(separator: ", ")
            let more = item.conflictingNames.count > 2 ? "…" : ""
            return "• \(item.archiveName) → \(names)\(more)"
        }.joined(separator: "\n")
        let remaining = archives.count > 3
            ? t("\n…另有 \(archives.count - 3) 个压缩包存在同名冲突", "\n…另有 \(archives.count - 3) 個封存檔存在同名衝突", "\n…and \(archives.count - 3) more conflicting archive(s)", "\n…ほか \(archives.count - 3) 件の書庫で重複あり")
            : ""
        return t(
            "以下目标路径已存在同名文件或文件夹，是否覆盖？\n\n\(previewLines)\(remaining)",
            "以下目標路徑已存在同名檔案或資料夾，是否覆蓋？\n\n\(previewLines)\(remaining)",
            "Existing files or folders were found at the destination for:\n\n\(previewLines)\(remaining)\n\nDo you want to overwrite them?",
            "以下の展開先に同名の項目が既に存在します。上書きしますか？\n\n\(previewLines)\(remaining)"
        )
    }

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

    // MARK: - v1.0.2 Updates, Preferences, Comments, Batch & Shortcuts
    var checkForUpdatesMenuTitle: String { t("检查更新…", "檢查更新…", "Check for Updates…", "アップデートを確認…") }
    var checkForUpdatesBtn: String { t("检查更新", "檢查更新", "Check Updates", "更新を確認") }
    var checkingUpdatesLabel: String { t("正在检查更新…", "正在檢查更新…", "Checking for updates…", "確認中…") }
    var autoCheckUpdatesTitle: String { t("自动检查更新", "自動檢查更新", "Check for Updates Automatically", "アップデートを自動確認") }
    var autoCheckUpdatesSubtitle: String { t("每日静默检测 GitHub Releases 新版与 SHA-256 校验", "每日靜默偵測 GitHub Releases 新版與 SHA-256 校驗", "Daily quiet check against GitHub Releases & SHA-256", "1 日 1 回 GitHub Releases と SHA-256 を確認") }
    var updateAvailableTitle: String { t("发现新版本", "發現新版本", "Update Available", "新しいバージョンが利用可能") }
    var updateUpToDateTitle: String { t("已是最新版本", "已是最新版本", "You’re Up to Date", "最新バージョンです") }
    func updateUpToDateMessage(_ version: String) -> String {
        t("BoltZip \(version) 已是当前 1.x 主线最新版。", "BoltZip \(version) 已是目前 1.x 主線最新版。", "BoltZip \(version) is the latest version on the 1.x track.", "BoltZip \(version) は 1.x 系統の最新版です。")
    }
    func updateSummaryLine(current: String, latest: String) -> String {
        t("当前 v\(current) → 最新 v\(latest)", "目前 v\(current) → 最新 v\(latest)", "v\(current) → v\(latest)", "現在 v\(current) → 最新 v\(latest)")
    }
    var updateDownloadVerifyBtn: String { t("下载并校验更新 (.dmg)", "下載並校驗更新 (.dmg)", "Download & Verify (.dmg)", "ダウンロードして検証 (.dmg)") }
    var updateDownloadingStatus: String { t("正在下载并校验 SHA-256…", "正在下載並校驗 SHA-256…", "Downloading & verifying SHA-256…", "ダウンロードと SHA-256 検証中…") }
    var updateVerifiedOpenBtn: String { t("校验通过 · 立即打开安装包", "校驗通過 · 立即開啟安裝包", "Verified · Open Installer", "検証完了 · インストーラを開く") }
    var updateViewOnGitHub: String { t("在 GitHub 查看", "在 GitHub 查看", "View on GitHub", "GitHub で見る") }
    var updateSkipVersionBtn: String { t("跳过此版本", "跳過此版本", "Skip Version", "このバージョンをスキップ") }
    var updateLaterBtn: String { t("稍后提醒", "稍後提醒", "Later", "後で") }

    var defaultExtractDestLabel: String { t("默认解压位置", "預設解壓位置", "Default Extract Location", "既定の展開先") }
    var extractDestSameFolder: String { t("压缩包所在目录", "封存檔所在目錄", "Same Folder", "書庫と同じフォルダ") }
    var extractDestDownloads: String { t("“下载”文件夹", "「下載」資料夾", "Downloads", "ダウンロード") }
    var extractDestAsk: String { t("每次询问", "每次詢問", "Ask Each Time", "毎回確認") }
    var defaultExtractModeLabel: String { t("默认解压模式", "預設解壓模式", "Default Extract Mode", "既定の展開モード") }
    var extractModeSmart: String { t("智能解压", "智慧解壓", "Smart Extract", "スマート展開") }
    var extractModeSubfolder: String { t("同名文件夹", "同名資料夾", "Subfolder", "同名フォルダ") }
    var preserveSymlinksTitle: String { t("保留安全符号链接", "保留安全符號連結", "Preserve Symlinks", "安全なシンボリックリンクを保持") }
    var preserveSymlinksSubtitle: String { t("打包时以链接形式写入相对符号链接而非拷贝目标", "打包時以連結形式寫入相對符號連結而非拷貝目標", "Archive relative symlinks cleanly without dereferencing", "実体コピーせず相対リンクとして書庫に格納") }
    var restoreSymlinksTitle: String { t("解压还原安全符号链接", "解壓還原安全符號連結", "Restore Safe Symlinks", "安全なシンボリックリンクを復元") }
    var restoreSymlinksSubtitle: String { t("自动拦截指向解压目录外或绝对路径的危险链接", "自動攔截指向解壓目錄外或絕對路徑的危險連結", "Restore links while blocking path-escaping targets", "展開先外を指す危険なリンクを自動ブロック") }
    var moveArchiveToTrashToggle: String { t("完成后将原压缩包移至废纸篓", "完成後將原封存檔移至垃圾桶", "Move Archive to Trash When Done", "完了後に元の書庫をゴミ箱へ移動") }
    var moveSourcesToTrashToggle: String { t("完成后将源文件移至废纸篓", "完成後將來源檔案移至垃圾桶", "Move Source Files to Trash When Done", "完了後に元ファイルをゴミ箱へ移動") }
    var clearRecentsBtn: String { t("清空", "清空", "Clear", "消去") }

    var archiveCommentTitle: String { t("归档注释", "封存檔註解", "Archive Comment", "書庫コメント") }
    var archiveCommentPlaceholder: String { t("输入可选的 ZIP 归档说明注释…", "輸入選填的 ZIP 封存檔說明註解…", "Optional archive note…", "ZIP 書庫コメント (任意)…") }
    var archiveCommentEditBtn: String { t("编辑注释", "編輯註解", "Edit Comment", "コメント編集") }
    var archiveCommentEmpty: String { t("无注释", "無註解", "No comment", "コメントなし") }
    var zipAddAlgoLabel: String { t("新增条目算法", "新增項目演算法", "Add Entry Algorithm", "追加時の圧縮方式") }
    func backToParentArchive(_ name: String) -> String {
        t("返回外层：\(name)", "返回外層：\(name)", "Back to \(name)", "親書庫へ戻る: \(name)")
    }
    var selectExtractDestTitle: String { t("选择解压目标文件夹", "選擇解壓目標資料夾", "Select Destination Folder", "展開先フォルダを選択") }
    var batchDropTitle: String { t("检测到多个压缩包", "偵測到多個封存檔", "Multiple Archives Dropped", "複数の書庫を検出") }
    func batchDropMessage(_ count: Int) -> String {
        t("你拖入了 \(count) 个压缩包，请选择操作方式：", "你拖入了 \(count) 個封存檔，請選擇操作方式：", "You dropped \(count) archives. Choose an action:", "\(count) 件の書庫がドロップされました。操作を選択してください:")
    }
    var batchDropSmartExtractAll: String { t("全部智能解压", "全部智慧解壓", "Smart Extract All", "すべてスマート展開") }
    var batchDropSubfolderAll: String { t("各自解压到同名文件夹", "各自解壓至同名資料夾", "Extract Each to Subfolder", "個別のフォルダへ展開") }
    var batchDropRepack: String { t("合并打包为新压缩包", "合併打包為新封存檔", "Repack into New Archive", "まとめて新しい書庫を作成") }

    var confirmDeleteTitle: String { t("确认从压缩包中删除", "確認從封存檔中刪除", "Delete From Archive?", "書庫から削除しますか？") }
    func confirmDeleteMessage(_ count: Int) -> String {
        t("将直接从当前 ZIP 中移除选中的 \(count) 个条目（此操作不可撤销）。", "將直接從目前 ZIP 中移除選取的 \(count) 個項目（此操作無法復原）。", "Remove \(count) selected item(s) permanently from this ZIP archive?", "選択した \(count) 件の項目を ZIP から完全に削除しますか？")
    }
    var confirmDeleteBtn: String { delete }
    var saveBtn: String { t("保存", "儲存", "Save", "保存") }
    func quickLookTooLargeStatus(_ name: String) -> String {
        t("预览已跳过（超过 50 MB）：\(name)", "預覽已跳過（超過 50 MB）：\(name)", "Quick Look skipped (> 50 MB): \(name)", "プレビューをスキップ (50 MB 超): \(name)")
    }
}
