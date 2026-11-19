(() => {
  const siteI18n = {
    "zh-Hans": {
      htmlLang: "zh-CN",
      pageTitle: "BoltZip v1.0.2 / v0.9.3 — Apple Silicon & macOS 12–26 开源极速压缩工作台",
      navDownload: "版本下载",
      navSim: "交互演示",
      navFeat: "核心特性",
      navAlgo: "开源算法",
      navBuild: "构建指南",
      navGitHub: "GitHub 开源仓库",
      heroBadge: "v1.0.2 Apple Silicon (macOS 26+) · v0.9.3 Universal (macOS 12–26) · MIT",
      heroTitle: "<span class=\"gradient-text\">快如闪电，通透如玻</span><br />让 macOS 压缩像桌面一样顺手。",
      heroDesc: "告别双击就一股脑解压一地的传统体验。BoltZip 基于纯正开源压缩底座（zlib · Zstandard · LZMA2 · bzip2 · LZ4 · libarchive），原生还原「包内直览与原地增删改、直接拖出到访达、大文件分块流式引擎、安全符号链接、多核并行、自动删除 .DS_Store、GBK 乱码自愈与访达一级 Bolt › 菜单」，提供面向 Apple Silicon 的全新 v1.0.2 与全机兼容的 v0.9.3 双轨安装镜像。",
      heroCtaDownload: "⬇ 下载最新版 v1.0.2 (.dmg)",
      heroCtaLegacy: "🛡 Intel / 旧版兼容 v0.9.3",
      heroCta1: "▶ 体验交互模拟器",
      quickLatestPill: "<strong>v1.0.2 新版</strong> · M 系列芯片 + macOS 26+",
      quickLegacyPill: "<strong>v0.9.3 兼容版</strong> · Intel Mac / macOS 12–15",
      stat1Val: "全格式 + 多核并行",
      stat2Val: "一级右键 Bolt ›",
      stat2Lbl: "FinderSync + 悬浮进度窗 + .dmg 安装",
      stat3Val: "4 语种随系统切换",
      stat3Lbl: "简中 · 繁中 · English · 日本語",
      archTitle: "BoltZip Engine · 分层架构",
      archLayer1: "macOS 26+ 原生 Liquid Glass（v0.9.3 兼容 macOS 12–15）· 访达 Bolt › 悬浮窗",
      archLayer2: "ZIP64 / 分卷 .z01 / 原地增删改 / RAR5 / WinZip AE-2 / GB18030 自动识别",
      simTitle: "Windows Zip 经典交互 · 实时界面模拟器",
      simSub: "点击工具栏体验「包内直览、自动剔除 .DS_Store、GBK 乱码一键自愈与 CRC32 校验」",
      simDocTitle: "2026_交付包_v2.zip",
      simBtnExtract: "智能解压",
      simBtnAdd: "包内添加",
      simBtnDelete: "删除",
      simBtnVerify: "完整性校验",
      simBtnGbkMock: "模拟 Windows GBK 乱码",
      simBtnGbkFix: "✨ 一键智能修复 GBK 乱码",
      simEncodingLbl: "编码:",
      simEncAuto: "智能自动 (GB18030/UTF-8)",
      simEncCp437: "原始 CP437 (未纠偏)",
      simEncUtf8: "强制 UTF-8",
      simSearchPh: "过滤包内文件...",
      simTreeTitle: "归档目录树",
      simTreeRoot: "📦 根目录 (Archive)",
      simRootCrumb: "📦 根目录",
      simCleanTitle: "干净打包保护",
      simCleanVal: "已过滤 <code>.DS_Store / __MACOSX</code>",
      colName: "名称",
      colOrigSize: "原始大小",
      colPackedSize: "压缩后",
      colRatio: "压缩率",
      colAlgo: "开源算法",
      colStatus: "校验 / 加密",
      folderTag: "文件夹",
      statusRight: "v1.0.2 Apple Silicon · v0.9.3 LTS",
      statusBarReady: "就绪 · 双击文件夹进入，单击文件查看详情",
      statusSelectedFmt: "已选中：{name} · {detail}",
      statusVerifyTag: "校验",
      toastQuickLook: "👁 <strong>Quick Look 快速预览</strong>：已从内存解密/解码 <code>{name}</code>（无需解压整个压缩包）。",
      toastSmartExtract: "📂 <strong>智能解压预览</strong>：检测到压缩包根目录含多个条目，将自动释放到 <code>~/Downloads/2026_交付包_v2/</code>，并自动删除 <code>.DS_Store</code> 等 Mac 隐藏文件。",
      newFilePrefix: "新增说明_",
      toastAddedFmt: "➕ <strong>包内原地添加成功</strong>：已将 <code>{name}</code> 写入归档并过滤 <code>.DS_Store</code>，原有文件未发生重压缩。",
      toastDeleteNeedSelect: "⚠️ 请先在右侧列表中单击选中一个文件或目录。",
      toastDeletedFmt: "🗑 已从归档移除 <code>{name}</code> 并重建中央目录。",
      toastVerifyPassFmt: "🛡 <strong>完整性校验通过</strong>：已验证 {count} 个条目（CRC32 + WinZip AE-2 HMAC-SHA1），0 个损坏。",
      toastGbkGarbled: "⚠️ 已切换至未纠偏原始字节：Windows 压缩包中的中文变成了乱码，点击按钮体验自动修复！",
      toastGbkFixed: "✨ <strong>GB18030 / CP936 自动识别生效</strong>：中文文件名已无损还原！",
      toastResetDemo: "🔄 示例归档条目的更改已随示例保留，已更新界面语言显示。",
      entryNameFinance: "财务报表_2026Q4.xlsx",
      entryNameDelivery: "交付说明与环境配置.pdf",
      entryNameArchDiagram: "架构设计图.png",
      featHead: "为什么 macOS 也需要一款「Windows 级」压缩软件？",
      featSub: "针对 macOS 原生归档工具高频痛点逐一工程级重塑",
      f1Title: "像资源管理器一样「包内直览与原地增删改」",
      f1Desc: "无需全量解压即可浏览目录树、嵌套压缩包钻取回退、空格 Quick Look 预览、直接拖出到访达、拖入文件进 ZIP、查看/编辑归档注释，未改动文件零重压缩。",
      f2Title: "自动删除 .DS_Store 等垃圾文件",
      f2Desc: "打包、包内追加与解压时默认自动剔除 <code>.DS_Store</code>、<code>__MACOSX</code> 与 <code>._*</code>，发给 Windows/Linux 同事干干净净。",
      f3Title: "Smart 智能解压 & 默认文件关联",
      f3Desc: "单一根目录直接释放不套娃，多文件自动建同名文件夹；设置内可一键把 ZIP/RAR/7z/TAR 设为 BoltZip 默认打开并换上 17 套分格式定制图标。",
      f4Title: "GBK / Shift-JIS 乱码自愈",
      f4Desc: "自动识别 Windows 工具打包的无 UTF-8 标记文件名（GB18030 / Big5 / Shift-JIS / EUC-KR）。",
      f5Title: "RAR/RAR5 + WinZip AE-2 + 多核并行",
      f5Desc: "完整支持 RAR/RAR5 浏览解压、WinZip AE-2 AES-256 加密互通与安全符号链接，并采用 64 MB+ 真流式引擎与多核并发加速。",
      f6Title: "访达右键「Bolt ›」独立悬浮进度窗 & .dmg 安装镜像",
      f6Desc: "提供 Retina 拖拽安装 <code>.dmg</code> 镜像；原生 <code>FinderSync</code> 菜单支持智能解压、自定义解压与多选分别压缩为 ZIP，附带 <code>boltzip</code> CLI（含 <code>add/rm/mv/--json</code>）。",
      f7Title: "双轨版本：v1.0.2 Apple Silicon 与 v0.9.3 Universal",
      f7Desc: "<code>v1.0.2</code> 面向 Apple Silicon（<code>arm64</code>）+ macOS 26+ 深度打造，内置 GitHub Releases 自动更新检查；Intel Mac 或 macOS 12–15 用户可随时选择内置静态 <code>libarchive 3.7.7</code> 的 <code>v0.9.3 Universal</code> 兼容版。",
      f8Title: "macOS 26+ 原生三层液态玻璃 & 统一背景体系",
      f8Desc: "工作台、设置、压缩向导全面采用原生 Liquid Glass，支持配色预设、透明度与模糊深度调节；v0.9.3 在 macOS 12–15 自动切换纯净原生界面。",
      algoTitle: "全栈开源压缩算法引擎 · 场景对比",
      algoSub: "核心算法均静态编译自成熟开源 C 实现，可审计、无第三方动态库依赖",
      algoControlLbl: "选择负载场景（参考模型对比，客户端内支持对当前 Mac 实时跑分）：",
      tabCode: "源码 & JSON",
      tabDocs: "文档 & 日志",
      tabBinary: "程序 & 资源包",
      metricRatioLbl: "压缩率表现",
      metricSpeedLbl: "吞吐速度倾向",
      workloads: {
        code: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 78, speed: 92, ratioText: "节省 78%", speedText: "极快 (~450 MB/s 级)" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 标准默认 · 全平台通用", ratio: 71, speed: 58, ratioText: "节省 71%", speedText: "均衡 (~120 MB/s 级)" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 84, speed: 24, ratioText: "节省 84%", speedText: "高比慢速" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 75, speed: 28, ratioText: "节省 75%", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 实时流场景", ratio: 54, speed: 99, ratioText: "节省 54%", speedText: "超快 (>1 GB/s 级)" }
        ],
        docs: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 68, speed: 90, ratioText: "节省 68%", speedText: "极快" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 标准默认 · Windows 互通", ratio: 63, speed: 60, ratioText: "节省 63%", speedText: "均衡" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 74, speed: 22, ratioText: "节省 74%", speedText: "高压缩率" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 67, speed: 30, ratioText: "节省 67%", speedText: "中等" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 实时流场景", ratio: 46, speed: 99, ratioText: "节省 46%", speedText: "极限速度" }
        ],
        binary: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 49, speed: 88, ratioText: "节省 49%", speedText: "极快" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 标准默认 · 全平台通用", ratio: 42, speed: 54, ratioText: "节省 42%", speedText: "均衡" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 57, speed: 20, ratioText: "节省 57%", speedText: "极限省空间" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 44, speed: 26, ratioText: "节省 44%", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 快速打包分发", ratio: 31, speed: 98, ratioText: "节省 31%", speedText: "超快" }
        ]
      },
      dlTitle: "选择适合你 Mac 的 BoltZip 版本",
      dlSub: "全版本均已打包带「拖拽至 Applications」引导页面的 .dmg 安装镜像、便携 .zip 与 SHA-256 校验清单",
      matcherTitle: "快速定位你的 Mac 架构与系统：",
      matcherAll: "对比全部版本",
      matcherLatest: "⚡ Apple Silicon (M 系列) + macOS 26+",
      matcherLegacy: "🛡 Intel Mac 或 macOS 12–15",
      matchedBadge: "✓ 推荐匹配你的 Mac",
      latestTag: "最新正式版 · v1.0.2",
      latestTitle: "BoltZip v1.0.2 — Apple Silicon 专属版",
      latestB1: "原生纯 arm64 架构编译，内置 17 套分格式定制 Retina 文件图标与 64 MB+ 真流式引擎",
      latestB2: "全面启用 macOS 26 原生三层同心圆角液态玻璃与滚动边缘效果（工作台 / 设置 / 进度浮窗）",
      latestB3: "支持拖拽导出到访达、安全符号链接、嵌套归档钻取、GitHub 在线检查更新与 .dmg 拖拽安装",
      latestDmgBtn: "⬇ 下载 v1.0.2 安装镜像 (.dmg · 23.2 MB)",
      dlZipArm64: "便携包 (.zip · 21.8 MB)",
      legacyTag: "长期兼容版 · v0.9.3",
      legacyTitle: "BoltZip v0.9.3 — Universal 全兼容版",
      legacyB1: "双架构原生支持 Intel x86_64 与 M 系列，覆盖 macOS 12 Monterey ~ macOS 26",
      legacyB2: "静态内置 libarchive 3.7.7 + zstd/xz/lz4，旧系统同样稳健支持 RAR/RAR5 与 7z 中文包",
      legacyB3: "macOS 12–15 自动切换纯净原生界面，同样提供 .dmg 拖拽安装、多核并行与默认关联",
      legacyDmgBtn: "⬇ 下载 v0.9.3 兼容镜像 (.dmg · 10 MB)",
      dlZipUni: "便携包 (.zip · 7.6 MB)",
      verifyTip: "🛡 <strong>SHA-256 完整性校验</strong>：下载后可在终端执行 <code>shasum -a 256 -c BoltZip-1.0.2-SHA256SUMS.txt</code>（或 <code>0.9.3</code>）核对哈希。",
      allReleasesBtn: "所有 GitHub Releases ↗",
      legacyBranchBtn: "legacy/macos-12 分支 ↗",
      qsTitle: "从 GitHub 克隆并构建 BoltZip",
      qsSub: "main 分支专攻 Apple Silicon (macOS 26+)，legacy/macos-12 分支保留 macOS 12–26 Universal 构建脚本",
      qsStep1: "1. 克隆并打包 .app 与 .dmg",
      qsStep2: "2. 切换兼容分支或运行测试",
      qsStep3: "3. 使用 boltzip CLI",
      copyBtn: "复制",
      copiedBtn: "已复制 ✓",
      copyManualBtn: "请手动复制",
      footerDesc: "<strong>BoltZip v1.0.2</strong> (Apple Silicon) · <strong>v0.9.3 LTS</strong> (macOS 12–26 Universal)"
    },
    "zh-Hant": {
      htmlLang: "zh-TW",
      pageTitle: "BoltZip v1.0.2 / v0.9.3 — Apple Silicon & macOS 12–26 開源極速壓縮工作台",
      navDownload: "版本下載",
      navSim: "互動模擬",
      navFeat: "核心功能",
      navAlgo: "開源演算法",
      navBuild: "建置指南",
      navGitHub: "GitHub 專案",
      heroBadge: "v1.0.2 Apple Silicon (macOS 26+) · v0.9.3 Universal (macOS 12–26) · MIT",
      heroTitle: "<span class=\"gradient-text\">快如閃電，通透如玻</span><br />讓 macOS 壓縮像桌面一樣順手。",
      heroDesc: "告別雙擊就整包解壓一地的困擾。BoltZip 結合純淨開源演算法核心，完整提供「包內直覽與原地增刪修改、直接拖曳匯出至 Finder、大檔分塊串流引擎、安全符號連結、RAR/RAR5 解壓、多核並行、自動刪除 .DS_Store 與 Finder 第一層 Bolt › 選單」，同步提供 Apple Silicon 新版 v1.0.2 與 Intel/舊系統兼容版 v0.9.3。",
      heroCtaDownload: "⬇ 下載最新版 v1.0.2 (.dmg)",
      heroCtaLegacy: "🛡 Intel / 舊版相容 v0.9.3",
      heroCta1: "▶ 體驗互動模擬器",
      quickLatestPill: "<strong>v1.0.2 新版</strong> · M 系列晶片 + macOS 26+",
      quickLegacyPill: "<strong>v0.9.3 相容版</strong> · Intel Mac / macOS 12–15",
      stat1Val: "全格式 + 多核並行",
      stat2Val: "第一層右鍵 Bolt ›",
      stat2Lbl: "FinderSync + 懸浮進度窗 + .dmg 安裝",
      stat3Val: "4 國語言自動切換",
      stat3Lbl: "簡中 · 繁中 · English · 日本語",
      archTitle: "BoltZip Engine · 分層架構",
      archLayer1: "macOS 26+ 原生 Liquid Glass（v0.9.3 相容 macOS 12–15）· Finder Bolt › 懸浮窗",
      archLayer2: "ZIP64 / 分卷 .z01 / 原地增刪修改 / RAR5 / WinZip AE-2 / GB18030 自動偵測",
      simTitle: "Windows Zip 經典操作 · 即時介面模擬器",
      simSub: "點擊工具列體驗「封存檔內建瀏覽、自動清除 .DS_Store、Windows 中文亂碼修正與 CRC32 驗證」",
      simDocTitle: "2026_交付包_v2.zip",
      simBtnExtract: "智慧解壓",
      simBtnAdd: "包內加入",
      simBtnDelete: "刪除",
      simBtnVerify: "完整性驗證",
      simBtnGbkMock: "模擬 Windows GBK 亂碼",
      simBtnGbkFix: "✨ 一鍵智慧修復 GBK 亂碼",
      simEncodingLbl: "編碼:",
      simEncAuto: "智慧自動 (GB18030/UTF-8)",
      simEncCp437: "原始 CP437 (未修正)",
      simEncUtf8: "強制 UTF-8",
      simSearchPh: "過濾封存檔內項目...",
      simTreeTitle: "封存目錄樹",
      simTreeRoot: "📦 根目錄 (Archive)",
      simRootCrumb: "📦 根目錄",
      simCleanTitle: "純淨封裝保護",
      simCleanVal: "已過濾 <code>.DS_Store / __MACOSX</code>",
      colName: "名稱",
      colOrigSize: "原始大小",
      colPackedSize: "壓縮後",
      colRatio: "節省率",
      colAlgo: "開源演算法",
      colStatus: "校驗 / 加密",
      folderTag: "資料夾",
      statusRight: "v1.0.2 Apple Silicon · v0.9.3 LTS",
      statusBarReady: "就緒 · 雙擊資料夾進入，單擊項目檢視詳情",
      statusSelectedFmt: "已選取：{name} · {detail}",
      statusVerifyTag: "驗證",
      toastQuickLook: "👁 <strong>Quick Look 快速預覽</strong>：已於記憶體解密/解碼 <code>{name}</code>（無須解壓整份封存檔）。",
      toastSmartExtract: "📂 <strong>智慧解壓預覽</strong>：偵測到根目錄包含多個項目，將自動釋放至 <code>~/Downloads/2026_交付包_v2/</code>，並自動清除 <code>.DS_Store</code> 等系統垃圾。",
      newFilePrefix: "新增說明_",
      toastAddedFmt: "➕ <strong>原地加入成功</strong>：已將 <code>{name}</code> 寫入封存檔並過濾 <code>.DS_Store</code>，其餘檔案零重壓縮。",
      toastDeleteNeedSelect: "⚠️ 請先於右側列表中點選一個檔案或資料夾。",
      toastDeletedFmt: "🗑 已自封存檔移除 <code>{name}</code> 並重建中央目錄。",
      toastVerifyPassFmt: "🛡 <strong>完整性驗證通過</strong>：已完成 {count} 個項目的校驗（CRC32 + WinZip AE-2 HMAC-SHA1），0 個損毀。",
      toastGbkGarbled: "⚠️ 已切換至未修正原始位元組：Windows 封存檔中文檔名顯示亂碼，再點一次立即智慧還原！",
      toastGbkFixed: "✨ <strong>GB18030 / CP936 自動識別生效</strong>：中文檔名已無損還原！",
      entryNameFinance: "財務報表_2026Q4.xlsx",
      entryNameDelivery: "交付說明與環境設定.pdf",
      entryNameArchDiagram: "架構設計圖.png",
      featHead: "為什麼 macOS 也需要「Windows 級」壓縮工具？",
      featSub: "針對 macOS 內建封存工具的高頻痛點全面重塑",
      f1Title: "如檔案總管般「包內直覽與原地增刪改」",
      f1Desc: "免全量解壓即可瀏覽目錄樹、巢狀壓縮檔鑽取返回、空白鍵呼叫 Quick Look 預覽、直接拖曳匯出至 Finder、拖曳新增檔案進 ZIP、檢視/編輯註解，未異動檔案零重壓縮。",
      f2Title: "自動刪除 .DS_Store 等隱藏垃圾檔案",
      f2Desc: "打包、包內追加與解壓時預設自動過濾 <code>.DS_Store</code>、<code>__MACOSX</code> 與 <code>._*</code>，跨平台分享乾淨清爽。",
      f3Title: "Smart 智慧解壓 & 預設檔案關聯",
      f3Desc: "單一根目錄直接釋放不套娃，多檔案自動建立同名資料夾；設定中可一鍵將 ZIP/RAR/7z/TAR 設為 BoltZip 預設開啟並換上 17 組分格式專屬圖示。",
      f4Title: "GBK / Shift-JIS 亂碼自動修正",
      f4Desc: "自動識別 Windows 工具建立的無 UTF-8 標記檔名（GB18030 / Big5 / Shift-JIS / EUC-KR）。",
      f5Title: "RAR/RAR5 + WinZip AE-2 + 多核並行",
      f5Desc: "完整支援 RAR/RAR5 瀏覽解壓、WinZip AE-2 AES-256 加密互通與安全符號連結，並透過 64 MB+ 真串流引擎與多核並行加速。",
      f6Title: "Finder 右鍵「Bolt ›」懸浮進度窗 & .dmg 安裝映像檔",
      f6Desc: "提供 Retina 拖曳安裝 <code>.dmg</code> 映像檔；原生 <code>FinderSync</code> 選單支援智慧解壓、指定目錄解壓與多選個別打包為 ZIP，同步內建 <code>boltzip</code> CLI（含 <code>add/rm/mv/--json</code>）。",
      f7Title: "雙軌版本：v1.0.2 Apple Silicon 與 v0.9.3 Universal",
      f7Desc: "<code>v1.0.2</code> 專為 Apple Silicon（<code>arm64</code>）+ macOS 26+ 深度最佳化，內建 GitHub Releases 檢查更新；Intel Mac 或 macOS 12–15 使用者可隨時選用內建靜態 <code>libarchive 3.7.7</code> 的 <code>v0.9.3 Universal</code> 相容版。",
      f8Title: "macOS 26+ 原生三層液態玻璃 & 統一視覺",
      f8Desc: "工作台、設定與壓縮精靈全面採用原生 Liquid Glass，支援背景色與透明度微調；v0.9.3 於 macOS 12–15 自動切換純淨原生介面。",
      algoTitle: "全端開源壓縮演算法引擎 · 場景比較",
      algoSub: "核心演算法皆由成熟開源 C 實作靜態編譯而來，可稽核、零第三方動態庫依賴",
      algoControlLbl: "選擇負載情境（參考模型比較，App 內支援對目前 Mac 即時跑分）：",
      tabCode: "原始碼 & JSON",
      tabDocs: "文件 & 日誌",
      tabBinary: "程式 & 資源包",
      metricRatioLbl: "壓縮率表現",
      metricSpeedLbl: "吞吐速度傾向",
      workloads: {
        code: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 78, speed: 92, ratioText: "節省 78%", speedText: "極快 (~450 MB/s 級)" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準預設 · 全平台通用", ratio: 71, speed: 58, ratioText: "節省 71%", speedText: "均衡 (~120 MB/s 級)" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 84, speed: 24, ratioText: "節省 84%", speedText: "高比慢速" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 75, speed: 28, ratioText: "節省 75%", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 即時串流情境", ratio: 54, speed: 99, ratioText: "節省 54%", speedText: "超快 (>1 GB/s 級)" }
        ],
        docs: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 68, speed: 90, ratioText: "節省 68%", speedText: "極快" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準預設 · Windows 互通", ratio: 63, speed: 60, ratioText: "節省 63%", speedText: "均衡" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 74, speed: 22, ratioText: "節省 74%", speedText: "高壓縮率" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 67, speed: 30, ratioText: "節省 67%", speedText: "中等" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 即時串流情境", ratio: 46, speed: 99, ratioText: "節省 46%", speedText: "極限速度" }
        ],
        binary: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 49, speed: 88, ratioText: "節省 49%", speedText: "極快" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準預設 · 全平台通用", ratio: 42, speed: 54, ratioText: "節省 42%", speedText: "均衡" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 格式", ratio: 57, speed: 20, ratioText: "節省 57%", speedText: "極限省空間" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 44, speed: 26, ratioText: "節省 44%", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 快速打包分發", ratio: 31, speed: 98, ratioText: "節省 31%", speedText: "超快" }
        ]
      },
      dlTitle: "選擇適合您 Mac 的 BoltZip 版本",
      dlSub: "雙版本皆已封裝含「拖曳至 Applications」引導畫面的 .dmg 安裝映像檔、可攜式 .zip 與 SHA-256 校驗清單",
      matcherTitle: "快速定位您的 Mac 架構與系統：",
      matcherAll: "比較全部版本",
      matcherLatest: "⚡ Apple Silicon (M 系列) + macOS 26+",
      matcherLegacy: "🛡 Intel Mac 或 macOS 12–15",
      matchedBadge: "✓ 推薦符合您的 Mac",
      latestTag: "最新正式版 · v1.0.2",
      latestTitle: "BoltZip v1.0.2 — Apple Silicon 專屬版",
      latestB1: "原生純 arm64 架構編譯，內建 17 組分格式定製 Retina 檔案圖示與 64 MB+ 真串流引擎",
      latestB2: "全面啟用 macOS 26 原生三層同心圓角液態玻璃與捲動邊緣效果（工作台 / 設定 / 進度浮窗）",
      latestB3: "支援拖曳匯出至 Finder、安全符號連結、巢狀歸檔鑽取、GitHub 線上檢查更新與 .dmg 拖曳安裝",
      latestDmgBtn: "⬇ 下載 v1.0.2 安裝映像檔 (.dmg · 23.2 MB)",
      dlZipArm64: "可攜版 (.zip · 21.8 MB)",
      legacyTag: "長期相容版 · v0.9.3",
      legacyTitle: "BoltZip v0.9.3 — Universal 全相容版",
      legacyB1: "雙架構原生支援 Intel x86_64 與 M 系列，涵蓋 macOS 12 Monterey ~ macOS 26",
      legacyB2: "靜態內建 libarchive 3.7.7 + zstd/xz/lz4，舊系統同樣穩定支援 RAR/RAR5 與 7z 中文包",
      legacyB3: "macOS 12–15 自動切換純淨原生介面，同樣提供 .dmg 拖曳安裝、多核並行與預設關聯",
      legacyDmgBtn: "⬇ 下載 v0.9.3 相容映像檔 (.dmg · 10 MB)",
      dlZipUni: "可攜版 (.zip · 7.6 MB)",
      verifyTip: "🛡 <strong>SHA-256 完整性校驗</strong>：下載後可於終端機執行 <code>shasum -a 256 -c BoltZip-1.0.2-SHA256SUMS.txt</code>（或 <code>0.9.3</code>）核對雜湊。",
      allReleasesBtn: "所有 GitHub Releases ↗",
      legacyBranchBtn: "legacy/macos-12 分支 ↗",
      qsTitle: "從 GitHub 取得並建置 BoltZip",
      qsSub: "main 分支專注 Apple Silicon (macOS 26+)，legacy/macos-12 分支保留 macOS 12–26 Universal 建置腳本",
      qsStep1: "1. 取得並打包 .app 與 .dmg",
      qsStep2: "2. 切換相容分支或執行測試",
      qsStep3: "3. 使用 boltzip CLI",
      copyBtn: "複製",
      copiedBtn: "已複製 ✓",
      copyManualBtn: "請手動複製",
      footerDesc: "<strong>BoltZip v1.0.2</strong> (Apple Silicon) · <strong>v0.9.3 LTS</strong> (macOS 12–26 Universal)"
    },
    "en": {
      htmlLang: "en",
      pageTitle: "BoltZip v1.0.2 / v0.9.3 — Apple Silicon & macOS 12–26 Archive Workbench",
      navDownload: "Downloads",
      navSim: "Simulator",
      navFeat: "Features",
      navAlgo: "Codecs",
      navBuild: "Build",
      navGitHub: "GitHub Repo",
      heroBadge: "v1.0.2 Apple Silicon (macOS 26+) · v0.9.3 Universal (macOS 12–26) · MIT",
      heroTitle: "<span class=\"gradient-text\">Lightning-fast archives.</span><br />Liquid-clear macOS craft.",
      heroDesc: "Stop extracting entire archives just to peek inside. BoltZip pairs pure open-source codecs (zlib, Zstandard, LZMA2, bzip2, LZ4, libarchive) with in-archive editing, Finder drag-out, chunked streaming I/O, safe symlinks, RAR/RAR5 extraction, multi-core speed, auto .DS_Store removal, CJK repair, and a top-level Finder “Bolt ›” HUD — offered as v1.0.2 (Apple Silicon) and v0.9.3 (Intel & macOS 12–26).",
      heroCtaDownload: "⬇ Download v1.0.2 (.dmg)",
      heroCtaLegacy: "🛡 Intel / Legacy macOS (v0.9.3)",
      heroCta1: "▶ Try Simulator",
      quickLatestPill: "<strong>v1.0.2 Latest</strong> · M-Series + macOS 26+",
      quickLegacyPill: "<strong>v0.9.3 LTS</strong> · Intel Mac / macOS 12–15",
      stat1Val: "All Formats + Multi-Core",
      stat2Val: "Top-Level Bolt ›",
      stat2Lbl: "FinderSync + Floating HUD + .dmg",
      stat3Val: "4 Languages",
      stat3Lbl: "zh-Hans · zh-Hant · EN · JA",
      archTitle: "BoltZip Engine · Layered Architecture",
      archLayer1: "macOS 26+ Native Liquid Glass (v0.9.3 supports macOS 12–15) · Finder Bolt › HUD",
      archLayer2: "ZIP64 / Split .z01 / In-Place Edit / RAR5 / WinZip AE-2 / GB18030 Auto-Detect",
      simTitle: "Windows-Zip Workflow · Live UI Simulator",
      simSub: "Test in-archive editing, .DS_Store cleanup, Windows GBK filename auto-fix & CRC32 checks",
      simDocTitle: "2026_Delivery_v2.zip",
      simBtnExtract: "Smart Extract",
      simBtnAdd: "Add Inside",
      simBtnDelete: "Delete",
      simBtnVerify: "Verify CRC",
      simBtnGbkMock: "Simulate GBK Mojibake",
      simBtnGbkFix: "✨ Auto-Fix GBK Garble",
      simEncodingLbl: "Encoding:",
      simEncAuto: "Auto (GB18030/UTF-8)",
      simEncCp437: "Raw CP437 (Unfixed)",
      simEncUtf8: "Force UTF-8",
      simSearchPh: "Filter archive entries...",
      simTreeTitle: "Archive Tree",
      simTreeRoot: "📦 Root (Archive)",
      simRootCrumb: "📦 Root",
      simCleanTitle: "Clean Packaging",
      simCleanVal: "Filtered <code>.DS_Store / __MACOSX</code>",
      colName: "Name",
      colOrigSize: "Original Size",
      colPackedSize: "Packed",
      colRatio: "Saved",
      colAlgo: "Open Codec",
      colStatus: "Verify / Crypto",
      folderTag: "Folder",
      statusRight: "v1.0.2 Apple Silicon · v0.9.3 LTS",
      statusBarReady: "Ready · Double-click folders to open, click files for details",
      statusSelectedFmt: "Selected: {name} · {detail}",
      statusVerifyTag: "Check",
      toastQuickLook: "👁 <strong>Quick Look Preview</strong>: Decoded/decrypted <code>{name}</code> in memory without extracting the whole archive.",
      toastSmartExtract: "📂 <strong>Smart Extract Preview</strong>: Multiple root items detected — extracting into <code>~/Downloads/2026_Delivery_v2/</code> and stripping <code>.DS_Store</code>.",
      newFilePrefix: "Release_Note_",
      toastAddedFmt: "➕ <strong>In-Place Add Complete</strong>: Added <code>{name}</code> and filtered <code>.DS_Store</code> with zero re-compression on untouched entries.",
      toastDeleteNeedSelect: "⚠️ Select a file or folder in the table first.",
      toastDeletedFmt: "🗑 Removed <code>{name}</code> from archive and rebuilt Central Directory.",
      toastVerifyPassFmt: "🛡 <strong>Integrity Check Passed</strong>: Verified {count} entries (CRC32 + WinZip AE-2 HMAC-SHA1), 0 corrupted.",
      toastGbkGarbled: "⚠️ Switched to raw unfixed bytes: Chinese filenames turned into CP437 mojibake — click the button to auto-heal!",
      toastGbkFixed: "✨ <strong>GB18030 / CP936 Auto-Detection Active</strong>: Filenames losslessly restored!",
      entryNameFinance: "Financial_Report_2026Q4.xlsx",
      entryNameDelivery: "Delivery_Guide_and_Setup.pdf",
      entryNameArchDiagram: "Architecture_Diagram.png",
      featHead: "Why macOS Deserves a Full-Featured Archive Workbench",
      featSub: "Engineered to solve every daily friction of the built-in macOS Archive Utility",
      f1Title: "Explorer-Style In-Archive Browse & Live Edit",
      f1Desc: "Browse folder trees and nested archives with breadcrumb back-navigation, press Space for Quick Look, drag items straight out to Finder, view/edit ZIP comments, or rename & delete inside ZIPs with zero recompression.",
      f2Title: "Auto-Delete .DS_Store & Mac Junk",
      f2Desc: "Automatically strips <code>.DS_Store</code>, <code>__MACOSX</code>, and <code>._*</code> during creation, append, and extraction so archives stay spotless on Windows/Linux.",
      f3Title: "Smart Extraction & Default File Associations",
      f3Desc: "Extracts single-root archives cleanly without nested wrappers; set BoltZip as your default handler for ZIP, RAR, 7z, and TAR inside Settings with 17 custom format icons.",
      f4Title: "CJK Mojibake Auto-Repair",
      f4Desc: "Auto-detects legacy codepages (GB18030 / Big5 / Shift-JIS / EUC-KR) for ZIP archives created without UTF-8 flags on Windows.",
      f5Title: "RAR/RAR5 + WinZip AE-2 + Multi-Core Speed",
      f5Desc: "Browse, verify, unlock, and extract RAR/RAR5 alongside WinZip AE-2 AES-256 ZIPs with 64 MB+ chunked streaming I/O, safe symlinks, and multi-core acceleration.",
      f6Title: "Top-Level Finder “Bolt ›” HUD & .dmg Drag Installer",
      f6Desc: "Ships as a Retina drag-to-Applications <code>.dmg</code>; native <code>FinderSync</code> menu adds Smart Extract, Extract to…, and per-item ZIP compression on multi-select, plus <code>boltzip</code> CLI (with <code>add/rm/mv/--json</code>).",
      f7Title: "Dual-Track Releases: v1.0.2 Apple Silicon & v0.9.3 Universal",
      f7Desc: "<code>v1.0.2</code> targets Apple Silicon (<code>arm64</code>) + macOS 26+ with built-in GitHub Releases updates; Intel Macs or macOS 12–15 run <code>v0.9.3 Universal</code> with statically bundled <code>libarchive 3.7.7</code>.",
      f8Title: "3-Layer Native Liquid Glass & Unified Backdrops",
      f8Desc: "Full native macOS 26 Liquid Glass across Explorer, Settings, and Compression Wizard with background color & blur tuning; v0.9.3 uses crisp native UI on macOS 12–15.",
      algoTitle: "Open-Source Compression Engine Lab · Comparison",
      algoSub: "Every codec is statically compiled from audited open-source C implementations with zero external dylibs",
      algoControlLbl: "Select workload profile (run real hardware benchmarks inside the macOS app):",
      tabCode: "Source & JSON",
      tabDocs: "Docs & Logs",
      tabBinary: "Binaries & Assets",
      metricRatioLbl: "Space Savings",
      metricSpeedLbl: "Throughput Profile",
      workloads: {
        code: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 78, speed: 92, ratioText: "78% saved", speedText: "Blazing (~450 MB/s class)" },
          { name: "DEFLATE (zlib -6)", sub: "Standard ZIP default · Universal", ratio: 71, speed: 58, ratioText: "71% saved", speedText: "Balanced (~120 MB/s class)" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip format", ratio: 84, speed: 24, ratioText: "84% saved", speedText: "Max ratio" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 75, speed: 28, ratioText: "75% saved", speedText: "Moderate" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · Real-time streams", ratio: 54, speed: 99, ratioText: "54% saved", speedText: "Ultra fast (>1 GB/s class)" }
        ],
        docs: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 68, speed: 90, ratioText: "68% saved", speedText: "Blazing" },
          { name: "DEFLATE (zlib -6)", sub: "Standard ZIP · Windows interop", ratio: 63, speed: 60, ratioText: "63% saved", speedText: "Balanced" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip format", ratio: 74, speed: 22, ratioText: "74% saved", speedText: "High density" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 67, speed: 30, ratioText: "67% saved", speedText: "Moderate" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · Real-time streams", ratio: 46, speed: 99, ratioText: "46% saved", speedText: "Top speed" }
        ],
        binary: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 49, speed: 88, ratioText: "49% saved", speedText: "Very fast" },
          { name: "DEFLATE (zlib -6)", sub: "Standard ZIP default", ratio: 42, speed: 54, ratioText: "42% saved", speedText: "Balanced" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip format", ratio: 57, speed: 20, ratioText: "57% saved", speedText: "Smallest archive" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 44, speed: 26, ratioText: "44% saved", speedText: "Moderate" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · Fast bundling", ratio: 31, speed: 98, ratioText: "31% saved", speedText: "Ultra fast" }
        ]
      },
      dlTitle: "Choose Your BoltZip Build",
      dlSub: "Every release ships with a Retina drag-to-Applications .dmg installer, portable .zip, source archives, and SHA-256 checksums",
      matcherTitle: "Quick-match your Mac hardware & OS:",
      matcherAll: "Compare Both",
      matcherLatest: "⚡ Apple Silicon (M-series) + macOS 26+",
      matcherLegacy: "🛡 Intel Mac or macOS 12–15",
      matchedBadge: "✓ Recommended Match",
      latestTag: "Latest Release · v1.0.2",
      latestTitle: "BoltZip v1.0.2 — Apple Silicon Edition",
      latestB1: "Pure arm64 native binary bundling 17 per-format Retina icons and a 64 MB+ streaming engine",
      latestB2: "Full native macOS 26 concentric Liquid Glass & scroll edge effects across Explorer, Settings, and HUD",
      latestB3: "Finder drag-out, safe symlinks, nested archive browsing, in-app GitHub updates & .dmg drag installer",
      latestDmgBtn: "⬇ Download v1.0.2 Installer (.dmg · 23.2 MB)",
      dlZipArm64: "Portable (.zip · 21.8 MB)",
      legacyTag: "Compatible LTS · v0.9.3",
      legacyTitle: "BoltZip v0.9.3 — Universal Edition",
      legacyB1: "Universal arm64 + Intel x86_64 supporting macOS 12 Monterey through macOS 26+",
      legacyB2: "Statically links libarchive 3.7.7 + zstd/xz/lz4 for full RAR/RAR5 & CJK 7z on legacy macOS",
      legacyB3: "Clean native UI on macOS 12–15, plus .dmg drag installer, multi-core speed & default associations",
      legacyDmgBtn: "⬇ Download v0.9.3 Universal (.dmg · 10 MB)",
      dlZipUni: "Portable (.zip · 7.6 MB)",
      verifyTip: "🛡 <strong>SHA-256 Verification</strong>: Run <code>shasum -a 256 -c BoltZip-1.0.2-SHA256SUMS.txt</code> (or <code>0.9.3</code>) to verify download integrity.",
      allReleasesBtn: "All GitHub Releases ↗",
      legacyBranchBtn: "legacy/macos-12 Branch ↗",
      qsTitle: "Clone & Build BoltZip from GitHub",
      qsSub: "main targets Apple Silicon (macOS 26+); legacy/macos-12 preserves Universal macOS 12–26 builds",
      qsStep1: "1. Clone & Build .app + .dmg",
      qsStep2: "2. Run Tests or Switch Legacy Branch",
      qsStep3: "3. Use boltzip CLI",
      copyBtn: "Copy",
      copiedBtn: "Copied ✓",
      copyManualBtn: "Copy manually",
      footerDesc: "<strong>BoltZip v1.0.2</strong> (Apple Silicon) · <strong>v0.9.3 LTS</strong> (macOS 12–26 Universal)"
    },
    "ja": {
      htmlLang: "ja",
      pageTitle: "BoltZip v1.0.2 / v0.9.3 — Apple Silicon & macOS 12–26 オープンソース書庫ワークベンチ",
      navDownload: "ダウンロード",
      navSim: "シミュレーター",
      navFeat: "主な機能",
      navAlgo: "圧縮エンジン",
      navBuild: "ビルド手順",
      navGitHub: "GitHub",
      heroBadge: "v1.0.2 Apple Silicon (macOS 26+) · v0.9.3 Universal (macOS 12–26) · MIT",
      heroTitle: "<span class=\"gradient-text\">稲妻の速さ、ガラスの透明感</span><br />macOS のための書庫スタジオ。",
      heroDesc: "中身を見るたびに丸ごと展開する必要はありません。BoltZip は純粋なオープンソース圧縮基盤に加え、書庫内直接編集・Finder ドラッグ書き出し・大容量チャンクストリーミング・安全なシンボリックリンク・RAR/RAR5 展開・マルチコア並列処理・.DS_Store 自動除外・文字化け補正・Finder「Bolt ›」進捗 HUD を搭載。Apple Silicon 専用 v1.0.2 と旧 OS/Intel 互換 v0.9.3 を用意しています。",
      heroCtaDownload: "⬇ 最新版 v1.0.2 (.dmg)",
      heroCtaLegacy: "🛡 Intel / 旧版互換 v0.9.3",
      heroCta1: "▶ シミュレーター体験",
      quickLatestPill: "<strong>v1.0.2 最新版</strong> · M シリーズ + macOS 26+",
      quickLegacyPill: "<strong>v0.9.3 互換版</strong> · Intel Mac / macOS 12–15",
      stat1Val: "全形式 + マルチコア",
      stat2Val: "第一階層 Bolt ›",
      stat2Lbl: "FinderSync + 進捗 HUD + .dmg",
      stat3Val: "4 言語対応",
      stat3Lbl: "簡中 · 繁中 · EN · 日本語",
      archTitle: "BoltZip Engine · レイヤード構造",
      archLayer1: "macOS 26+ ネイティブ Liquid Glass（v0.9.3 は macOS 12–15 対応）· Finder Bolt › HUD",
      archLayer2: "ZIP64 / 分割 .z01 / 書庫内直接編集 / RAR5 / WinZip AE-2 / 文字コード自動判別",
      simTitle: "Windows Zip 級ワークフロー · インタラクティブ体験",
      simSub: "書庫内編集、.DS_Store 自動除外、文字化け補正と整合性検証をブラウザで体験",
      simDocTitle: "2026_納品パック_v2.zip",
      simBtnExtract: "スマート展開",
      simBtnAdd: "書庫に追加",
      simBtnDelete: "削除",
      simBtnVerify: "整合性検証",
      simBtnGbkMock: "Windows 文字化けを再現",
      simBtnGbkFix: "✨ 文字化けを自動修復",
      simEncodingLbl: "文字コード:",
      simEncAuto: "自動判別 (GB18030/UTF-8)",
      simEncCp437: "生 CP437 (未補正)",
      simEncUtf8: "UTF-8 強制",
      simSearchPh: "書庫内のファイルを絞り込み...",
      simTreeTitle: "書庫ディレクトリツリー",
      simTreeRoot: "📦 ルート (Archive)",
      simRootCrumb: "📦 ルート",
      simCleanTitle: "クリーン圧縮保護",
      simCleanVal: "除外済み <code>.DS_Store / __MACOSX</code>",
      colName: "名前",
      colOrigSize: "元のサイズ",
      colPackedSize: "圧縮後",
      colRatio: "削減率",
      colAlgo: "圧縮方式",
      colStatus: "検証 / 暗号化",
      folderTag: "フォルダ",
      statusRight: "v1.0.2 Apple Silicon · v0.9.3 LTS",
      statusBarReady: "準備完了 · フォルダをダブルクリックで移動、クリックで詳細表示",
      statusSelectedFmt: "選択中：{name} · {detail}",
      statusVerifyTag: "検証",
      toastQuickLook: "👁 <strong>Quick Look プレビュー</strong>：全体を展開せずメモリ上で <code>{name}</code> をデコード／復号しました。",
      toastSmartExtract: "📂 <strong>スマート展開プレビュー</strong>：複数ルート項目を検出し <code>~/Downloads/2026_納品パック_v2/</code> へ展開（<code>.DS_Store</code> 自動除外）。",
      newFilePrefix: "追加メモ_",
      toastAddedFmt: "➕ <strong>書庫内追加完了</strong>：<code>.DS_Store</code> を除外しつつ <code>{name}</code> を追加（既存ファイルは再圧縮なし）。",
      toastDeleteNeedSelect: "⚠️ 右側の一覧からファイルまたはフォルダを選択してください。",
      toastDeletedFmt: "🗑 <code>{name}</code> を書庫から削除し、セントラルディレクトリを再構築しました。",
      toastVerifyPassFmt: "🛡 <strong>整合性検証に合格</strong>：{count} 件のエントリ（CRC32 + WinZip AE-2 HMAC-SHA1）に破損はありませんでした。",
      toastGbkGarbled: "⚠️ 未補正のバイト列に切り替えました：ファイル名が文字化けしています。ボタンで自動修復をお試しください！",
      toastGbkFixed: "✨ <strong>GB18030 / CP936 自動認識有効</strong>：ファイル名をロスレスで復元しました！",
      entryNameFinance: "財務レポート_2026Q4.xlsx",
      entryNameDelivery: "納品ガイドと環境設定.pdf",
      entryNameArchDiagram: "アーキテクチャ構成図.png",
      featHead: "macOS にも高機能な書庫ワークベンチを",
      featSub: "標準アーカイブユーティリティの不便さをエンジニアリングで解消",
      f1Title: "エクスプローラー風の書庫内閲覧 ＆ 直接編集",
      f1Desc: "全展開せず階層表示・入れ子書庫のドリルダウン戻り・Quick Look・Finder へのドラッグ書き出し・コメント編集・ZIP 内の追加／削除／リネームに対応（未変更項目は再圧縮ゼロ）。",
      f2Title: ".DS_Store 等 Mac ゴミファイルを自動削除",
      f2Desc: "圧縮・追記・展開時に <code>.DS_Store</code>、<code>__MACOSX</code>、<code>._*</code> を既定で除外し、Windows/Linux 共有もクリーンに。",
      f3Title: "スマート展開 ＆ 既定ファイル関連付け",
      f3Desc: "単一ルートフォルダならそのまま整理して展開。設定画面から ZIP / RAR / 7z / TAR の既定アプリをワンクリックで切り替え、17 種のフォーマット別アイコンを適用。",
      f4Title: "Shift-JIS / GBK 文字化け自動補正",
      f4Desc: "Windows 製ツールで作られた UTF-8 フラグなし書庫の文字コード（GB18030 / Big5 / Shift-JIS / EUC-KR）を自動判別します。",
      f5Title: "RAR/RAR5 + WinZip AE-2 + マルチコア高速化",
      f5Desc: "RAR / RAR5 の閲覧・検証・展開や WinZip AE-2 AES-256 暗号化、安全なシンボリックリンクに対応し、64 MB+ ストリーミングと並列処理で高速処理します。",
      f6Title: "Finder 右クリック「Bolt ›」HUD ＆ .dmg インストーラー",
      f6Desc: "Retina ドラッグ導入 <code>.dmg</code> を用意。<code>FinderSync</code> は個別 ZIP 圧縮・展開先指定・進捗 HUD を備え、<code>boltzip</code> CLI（<code>add/rm/mv/--json</code> 対応）も同梱します。",
      f7Title: "デュアルトラック：v1.0.2 Apple Silicon と v0.9.3 Universal",
      f7Desc: "<code>v1.0.2</code> は Apple Silicon（<code>arm64</code>）+ macOS 26+ 専用で GitHub Releases 自動更新を内蔵；Intel Mac や macOS 12–15 では静的 <code>libarchive 3.7.7</code> 内蔵の <code>v0.9.3 Universal</code> を選べます。",
      f8Title: "3層ネイティブ Liquid Glass ＆ 統一デザイン",
      f8Desc: "ワークスペース・設定・ウィザードまで macOS 26 Liquid Glass を適用し透明度を調整可能。v0.9.3 は macOS 12–15 でクリーンな標準 UI に切り替わります。",
      algoTitle: "オープンソース圧縮エンジン · 性能比較",
      algoSub: "すべてのコーデックは外部 dylib 不要の純粋 C 静的リンク実装です",
      algoControlLbl: "ワークロードを選択（アプリ内では実機ベンチマークも実行可能）：",
      tabCode: "ソースコード & JSON",
      tabDocs: "ドキュメント & ログ",
      tabBinary: "バイナリ & リソース",
      metricRatioLbl: "圧縮率バランス",
      metricSpeedLbl: "スループット傾向",
      workloads: {
        code: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 78, speed: 92, ratioText: "78% 削減", speedText: "爆速 (~450 MB/s 級)" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準 · 全OS互換", ratio: 71, speed: 58, ratioText: "71% 削減", speedText: "標準 (~120 MB/s 級)" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 形式", ratio: 84, speed: 24, ratioText: "84% 削減", speedText: "最高圧縮" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 75, speed: 28, ratioText: "75% 削減", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · リアルタイム向け", ratio: 54, speed: 99, ratioText: "54% 削減", speedText: "超高速 (>1 GB/s 級)" }
        ],
        docs: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 68, speed: 90, ratioText: "68% 削減", speedText: "高速" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準 · Windows 互換", ratio: 63, speed: 60, ratioText: "63% 削減", speedText: "標準" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 形式", ratio: 74, speed: 22, ratioText: "74% 削減", speedText: "高密度" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 67, speed: 30, ratioText: "67% 削減", speedText: "標準" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · リアルタイム向け", ratio: 46, speed: 99, ratioText: "46% 削減", speedText: "最速" }
        ],
        binary: [
          { name: "Zstandard (zstd -5)", sub: "ZIP Method 93 / .tar.zst", ratio: 49, speed: 88, ratioText: "49% 削減", speedText: "高速" },
          { name: "DEFLATE (zlib -6)", sub: "ZIP 標準", ratio: 42, speed: 54, ratioText: "42% 削減", speedText: "標準" },
          { name: "LZMA2 (xz -5)", sub: ".tar.xz / 7-Zip 形式", ratio: 57, speed: 20, ratioText: "57% 削減", speedText: "最小サイズ" },
          { name: "Bzip2 (libbz2 -6)", sub: "ZIP Method 12 / .tar.bz2", ratio: 44, speed: 26, ratioText: "44% 削減", speedText: "中低速" },
          { name: "LZ4 (lz4frame -3)", sub: ".tar.lz4 · 高速バンドル", ratio: 31, speed: 98, ratioText: "31% 削減", speedText: "超高速" }
        ]
      },
      dlTitle: "お使いの Mac に合う BoltZip を選択",
      dlSub: "全バージョンで Retina「Applications へドラッグ」画面付き .dmg インストーラー、ポータブル .zip、SHA-256 を提供",
      matcherTitle: "Mac のチップ・OS を選んで素早く判定：",
      matcherAll: "両バージョンを比較",
      matcherLatest: "⚡ Apple Silicon (Mシリーズ) + macOS 26+",
      matcherLegacy: "🛡 Intel Mac または macOS 12–15",
      matchedBadge: "✓ お使いの Mac に最適",
      latestTag: "最新リリース · v1.0.2",
      latestTitle: "BoltZip v1.0.2 — Apple Silicon 専用版",
      latestB1: "arm64 ネイティブ専用ビルド、17 種の拡張子別 Retina アイコンと 64 MB+ 真ストリーミング内蔵",
      latestB2: "macOS 26 ネイティブ同心円角 Liquid Glass とスクロール端効果をワークスペース・設定・HUD に全面適用",
      latestB3: "Finder ドラッグ書き出し・安全なシンボリックリンク・入れ子書庫・GitHub 自動更新・.dmg 導入に対応",
      latestDmgBtn: "⬇ v1.0.2 インストーラー (.dmg · 23.2 MB)",
      dlZipArm64: "ポータブル (.zip · 21.8 MB)",
      legacyTag: "長期互換版 · v0.9.3",
      legacyTitle: "BoltZip v0.9.3 — Universal 互換版",
      legacyB1: "Intel x86_64 ＆ Apple Silicon 両対応、macOS 12 Monterey 〜 macOS 26+ をカバー",
      legacyB2: "静的 libarchive 3.7.7 + zstd/xz/lz4 を内蔵し、旧 OS でも RAR/RAR5 や中国語 7z を高速処理",
      legacyB3: "macOS 12–15 では標準 UI へ自動最適化、同じく .dmg 導入・マルチコア・既定設定を搭載",
      legacyDmgBtn: "⬇ v0.9.3 互換版 (.dmg · 10 MB)",
      dlZipUni: "ポータブル (.zip · 7.6 MB)",
      verifyTip: "🛡 <strong>SHA-256 検証</strong>：ダウンロード後は <code>shasum -a 256 -c BoltZip-1.0.2-SHA256SUMS.txt</code>（または <code>0.9.3</code>）で検証できます。",
      allReleasesBtn: "全 GitHub Releases ↗",
      legacyBranchBtn: "legacy/macos-12 ブランチ ↗",
      qsTitle: "GitHub からクローンしてビルド",
      qsSub: "main は Apple Silicon (macOS 26+) 専用、legacy/macos-12 は macOS 12–26 Universal 構成を保持",
      qsStep1: "1. クローン＆.app / .dmg パッケージ化",
      qsStep2: "2. テスト実行または互換ブランチへ切替",
      qsStep3: "3. boltzip CLI を使用",
      copyBtn: "コピー",
      copiedBtn: "コピー完了 ✓",
      copyManualBtn: "手動コピー",
      footerDesc: "<strong>BoltZip v1.0.2</strong> (Apple Silicon) · <strong>v0.9.3 LTS</strong> (macOS 12–26 Universal)"
    }
  };

  let currentLang = "zh-Hans";
  let currentWorkload = "code";

  function dict() {
    return siteI18n[currentLang] || siteI18n["zh-Hans"];
  }

  function formatStr(template, vars) {
    return Object.entries(vars).reduce((acc, [k, v]) => acc.replaceAll(`{${k}}`, v), template);
  }

  const initialEntries = [
    { id: "src/", parent: "", name: "src", isDir: true, size: 0, packed: 0, method: "Folder", status: "OK", crc: "—" },
    { id: "docs/", parent: "", name: "docs", isDir: true, size: 0, packed: 0, method: "Folder", status: "OK", crc: "—" },
    {
      id: "finance_report",
      parent: "",
      nameKey: "entryNameFinance",
      garbledName: "²ÆÎñ±¨±í_2026Q4.xlsx",
      isDir: false,
      size: 1843200,
      packed: 492100,
      method: "DEFLATE",
      status: "AES-256",
      crc: "AE-2 HMAC"
    },
    {
      id: "delivery_guide",
      parent: "",
      nameKey: "entryNameDelivery",
      garbledName: "½»¸¶ËµÃ÷Óë»·¾³ÅäÖÃ.pdf",
      isDir: false,
      size: 4210800,
      packed: 3180400,
      method: "DEFLATE",
      status: "AES-256",
      crc: "AE-2 HMAC"
    },
    { id: "README.md", parent: "", name: "README.md", isDir: false, size: 14200, packed: 4820, method: "Zstd", status: "CRC32 OK", crc: "0x9A21F4B0" },
    { id: "src/BoltEngine.swift", parent: "src/", name: "BoltEngine.swift", isDir: false, size: 68400, packed: 16400, method: "Zstd", status: "CRC32 OK", crc: "0x41D8C209" },
    { id: "src/ZipCrypto.swift", parent: "src/", name: "ZipCrypto.swift", isDir: false, size: 32900, packed: 8900, method: "DEFLATE", status: "AES-256", crc: "AE-2 HMAC" },
    { id: "docs/arch_diagram", parent: "docs/", nameKey: "entryNameArchDiagram", garbledName: "¼Ü¹¹Éè¼ÆÍ¼.png", isDir: false, size: 2560000, packed: 2480000, method: "Store", status: "CRC32 OK", crc: "0xE71022A1" }
  ];

  let entries = structuredClone(initialEntries);
  let currentFolder = "";
  let selectedId = "finance_report";
  let gbkGarbledMode = false;
  let searchQuery = "";

  const treeEl = document.getElementById("simTree");
  const tableBody = document.getElementById("simTableBody");
  const crumbsEl = document.getElementById("simBreadcrumbs");
  const statusLeft = document.getElementById("simStatusLeft");
  const toastEl = document.getElementById("simToast");
  const encodingSelect = document.getElementById("simEncodingSelect");
  const gbkBtnText = document.getElementById("gbkBtnText");

  function fmtSize(bytes) {
    if (!bytes) return "—";
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(2) + " MB";
  }

  function displayName(entry) {
    if (gbkGarbledMode && entry.garbledName) return entry.garbledName;
    if (entry.nameKey && dict()[entry.nameKey]) return dict()[entry.nameKey];
    return entry.name;
  }

  let toastTimer = null;
  function showToast(html) {
    toastEl.innerHTML = html;
    toastEl.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.add("hidden"), 3800);
  }

  function renderTree() {
    const d = dict();
    const folders = [{ path: "", label: d.simTreeRoot }];
    entries.filter(e => e.isDir).forEach(folder => {
      folders.push({ path: folder.id, label: "📁 " + displayName(folder) });
    });

    treeEl.innerHTML = "";
    folders.forEach(f => {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.className = "tree-node" + (currentFolder === f.path ? " active" : "");
      btn.textContent = f.label;
      btn.onclick = () => {
        currentFolder = f.path;
        selectedId = null;
        renderAll();
      };
      li.appendChild(btn);
      treeEl.appendChild(li);
    });
  }

  function renderBreadcrumbs() {
    const d = dict();
    crumbsEl.innerHTML = "";
    const rootBtn = document.createElement("button");
    rootBtn.className = "crumb" + (currentFolder === "" ? " active" : "");
    rootBtn.textContent = d.simRootCrumb;
    rootBtn.onclick = () => {
      currentFolder = "";
      renderAll();
    };
    crumbsEl.appendChild(rootBtn);

    if (currentFolder) {
      const sep = document.createElement("span");
      sep.textContent = "/";
      sep.style.color = "#64748b";
      crumbsEl.appendChild(sep);

      const subBtn = document.createElement("button");
      subBtn.className = "crumb active";
      subBtn.textContent = "📁 " + currentFolder.replace(/\/$/, "");
      crumbsEl.appendChild(subBtn);
    }
  }

  function renderTable() {
    const d = dict();
    const q = searchQuery.trim().toLowerCase();
    const visible = entries.filter(e => {
      if (q) return displayName(e).toLowerCase().includes(q);
      return e.parent === currentFolder;
    });

    tableBody.innerHTML = "";
    visible.forEach(e => {
      const tr = document.createElement("tr");
      if (e.id === selectedId) tr.classList.add("selected");

      const ratio = e.isDir || !e.size ? "—" : (((1 - e.packed / e.size) * 100).toFixed(1) + "%");
      const badgeClass = e.status.includes("AES") ? "enc-badge" : "ok-badge";

      tr.innerHTML = `
        <td>
          <div class="name-cell">
            <span>${e.isDir ? "📁" : "📄"}</span>
            <span>${displayName(e)}</span>
          </div>
        </td>
        <td>${e.isDir ? d.folderTag : fmtSize(e.size)}</td>
        <td>${e.isDir ? "—" : fmtSize(e.packed)}</td>
        <td>${ratio === "—" ? "—" : `<span class="ratio-badge">${ratio}</span>`}</td>
        <td>${e.method}</td>
        <td><span class="${badgeClass}">${e.status}</span></td>
      `;

      tr.onclick = () => {
        selectedId = e.id;
        const detail = e.isDir ? d.folderTag : `${fmtSize(e.size)} · ${d.statusVerifyTag} ${e.crc}`;
        statusLeft.textContent = formatStr(d.statusSelectedFmt, { name: displayName(e), detail });
        renderTable();
      };

      tr.ondblclick = () => {
        if (e.isDir) {
          currentFolder = e.id;
          selectedId = null;
          renderAll();
        } else {
          showToast(formatStr(d.toastQuickLook, { name: displayName(e) }));
        }
      };

      tableBody.appendChild(tr);
    });

    if (!selectedId) {
      statusLeft.textContent = d.statusBarReady;
    } else {
      const active = entries.find(item => item.id === selectedId);
      if (active) {
        const detail = active.isDir ? d.folderTag : `${fmtSize(active.size)} · ${d.statusVerifyTag} ${active.crc}`;
        statusLeft.textContent = formatStr(d.statusSelectedFmt, { name: displayName(active), detail });
      }
    }
  }

  function renderAll() {
    gbkBtnText.textContent = gbkGarbledMode ? dict().simBtnGbkFix : dict().simBtnGbkMock;
    renderTree();
    renderBreadcrumbs();
    renderTable();
  }

  document.getElementById("btnExtractSmart").onclick = () => {
    showToast(dict().toastSmartExtract);
  };

  let addCounter = 1;
  document.getElementById("btnAddSimFile").onclick = () => {
    const d = dict();
    const newName = `${d.newFilePrefix}${addCounter++}.txt`;
    const newId = currentFolder + newName;
    entries.push({
      id: newId,
      parent: currentFolder,
      name: newName,
      isDir: false,
      size: 24576,
      packed: 6144,
      method: "Zstd",
      status: "CRC32 OK",
      crc: "0x7F1099AB"
    });
    selectedId = newId;
    renderAll();
    showToast(formatStr(d.toastAddedFmt, { name: newName }));
  };

  document.getElementById("btnDeleteSimFile").onclick = () => {
    const d = dict();
    if (!selectedId) {
      showToast(d.toastDeleteNeedSelect);
      return;
    }
    const target = entries.find(e => e.id === selectedId);
    if (!target) return;
    entries = entries.filter(e => e.id !== target.id && e.parent !== target.id);
    selectedId = null;
    renderAll();
    showToast(formatStr(d.toastDeletedFmt, { name: displayName(target) }));
  };

  document.getElementById("btnTestIntegrity").onclick = () => {
    const files = entries.filter(e => !e.isDir).length;
    showToast(formatStr(dict().toastVerifyPassFmt, { count: String(files) }));
  };

  function setGBKMode(garbled) {
    gbkGarbledMode = garbled;
    encodingSelect.value = garbled ? "cp437" : "auto";
    renderAll();
  }

  document.getElementById("btnToggleGBK").onclick = () => {
    setGBKMode(!gbkGarbledMode);
    if (gbkGarbledMode) {
      showToast(dict().toastGbkGarbled);
    } else {
      showToast(dict().toastGbkFixed);
    }
  };

  encodingSelect.onchange = (ev) => {
    setGBKMode(ev.target.value === "cp437");
  };

  document.getElementById("simSearch").oninput = (ev) => {
    searchQuery = ev.target.value;
    renderTable();
  };

  // Algorithm Lab Interactive Chart
  const algoRowsEl = document.getElementById("algoRows");
  function renderAlgorithms(kind) {
    currentWorkload = kind;
    const d = dict();
    const items = d.workloads[kind] || d.workloads.code;
    algoRowsEl.innerHTML = "";
    items.forEach(item => {
      const row = document.createElement("div");
      row.className = "algo-row";
      row.innerHTML = `
        <div class="algo-name">
          <strong>${item.name}</strong>
          <span>${item.sub}</span>
        </div>
        <div class="metric-bar-group">
          <div class="metric-label"><span>${d.metricRatioLbl}</span><strong>${item.ratioText}</strong></div>
          <div class="bar-track"><div class="bar-fill bar-ratio" style="width:${item.ratio}%"></div></div>
        </div>
        <div class="metric-bar-group">
          <div class="metric-label"><span>${d.metricSpeedLbl}</span><strong>${item.speedText}</strong></div>
          <div class="bar-track"><div class="bar-fill bar-speed" style="width:${item.speed}%"></div></div>
        </div>
      `;
      algoRowsEl.appendChild(row);
    });
  }

  document.querySelectorAll(".w-tab").forEach(tab => {
    tab.onclick = () => {
      document.querySelectorAll(".w-tab").forEach(t => t.classList.remove("active"));
      tab.classList.add("active");
      renderAlgorithms(tab.dataset.workload);
    };
  });

  document.querySelectorAll(".copy-btn").forEach(btn => {
    btn.onclick = async () => {
      const txt = btn.dataset.copy;
      const d = dict();
      try {
        await navigator.clipboard.writeText(txt);
        btn.textContent = d.copiedBtn;
        setTimeout(() => (btn.textContent = dict().copyBtn), 1600);
      } catch {
        btn.textContent = d.copyManualBtn;
        setTimeout(() => (btn.textContent = dict().copyBtn), 2000);
      }
    };
  });

  // Dual-Track Release Version Matcher & Quick-Jump
  const trackCards = document.querySelectorAll(".track-card");
  const matcherButtons = document.querySelectorAll("[data-track-filter]");

  function selectTrackFilter(filter) {
    matcherButtons.forEach(btn => {
      btn.classList.toggle("active", btn.dataset.trackFilter === filter);
    });
    trackCards.forEach(card => {
      const track = card.dataset.track;
      const isHighlight = filter !== "all" && track === filter;
      const isDim = filter !== "all" && track !== filter;
      card.classList.toggle("is-highlighted", isHighlight);
      card.classList.toggle("is-dimmed", isDim);
    });
  }

  matcherButtons.forEach(btn => {
    btn.onclick = () => selectTrackFilter(btn.dataset.trackFilter || "all");
  });

  document.querySelectorAll("[data-quick-track]").forEach(el => {
    el.addEventListener("click", (ev) => {
      const targetTrack = el.dataset.quickTrack || "all";
      selectTrackFilter(targetTrack);
      const downloadsSection = document.getElementById("downloads");
      if (downloadsSection) {
        if (el.tagName !== "A") {
          ev.preventDefault();
        }
        downloadsSection.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    });
  });

  trackCards.forEach(card => {
    card.addEventListener("click", (ev) => {
      if (ev.target.closest("a, button")) return;
      if (card.classList.contains("is-dimmed")) {
        selectTrackFilter(card.dataset.track || "all");
      }
    });
  });

  function applySiteLang(lang) {
    currentLang = siteI18n[lang] ? lang : "zh-Hans";
    const d = dict();
    document.documentElement.lang = d.htmlLang;
    document.title = d.pageTitle;

    document.querySelectorAll("[data-i18n]").forEach(el => {
      const k = el.dataset.i18n;
      if (d[k]) el.textContent = d[k];
    });
    document.querySelectorAll("[data-i18n-html]").forEach(el => {
      const k = el.dataset.i18nHtml;
      if (d[k]) el.innerHTML = d[k];
    });
    document.querySelectorAll("[data-i18n-placeholder]").forEach(el => {
      const k = el.dataset.i18nPlaceholder;
      if (d[k]) el.setAttribute("placeholder", d[k]);
    });

    renderAll();
    renderAlgorithms(currentWorkload);
  }

  const siteLangSelect = document.getElementById("siteLangSelect");
  if (siteLangSelect) {
    siteLangSelect.onchange = (e) => applySiteLang(e.target.value);
    const navLang = (navigator.language || "zh-CN").toLowerCase();
    let initial = "zh-Hans";
    if (navLang.startsWith("ja")) initial = "ja";
    else if (navLang.startsWith("zh-tw") || navLang.startsWith("zh-hk") || navLang.startsWith("zh-hant")) initial = "zh-Hant";
    else if (!navLang.startsWith("zh")) initial = "en";
    siteLangSelect.value = initial;
    applySiteLang(initial);
  } else {
    renderAll();
    renderAlgorithms(currentWorkload);
  }
})();
