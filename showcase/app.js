(() => {
  const siteI18n = {
    "zh-Hans": {
      htmlLang: "zh-CN",
      pageTitle: "BoltZip v1.0.0 — 为 Apple Silicon & macOS 26+ 打造的开源液态玻璃压缩工作台",
      navDownload: "下载安装包",
      navSim: "交互演示",
      navFeat: "核心特性",
      navAlgo: "开源算法",
      navBuild: "构建指南",
      navGitHub: "GitHub 开源仓库",
      heroBadge: "macOS 26+ Apple Silicon (arm64) · 原生 Liquid Glass · MIT 开源",
      heroTitle: "<span class=\"gradient-text\">快如闪电，通透如玻</span><br />让 macOS 压缩像桌面一样顺手。",
      heroDesc: "告别双击就一股脑解压一地的传统体验。BoltZip 基于纯正开源压缩底座（zlib · Zstandard · LZMA2 · bzip2 · LZ4 · libarchive），原生还原「包内浏览、直接增删改、自动删除 .DS_Store、GBK 乱码自愈、访达一级 Bolt 菜单（独立进度浮窗）与 macOS 26+ 原生液态玻璃」。",
      heroCtaDownload: "⬇ 下载 v1.0.0 Apple Silicon",
      heroCta1: "▶ 体验界面交互模拟器",
      heroCta2: "克隆源码并构建",
      stat1Val: "6 大开源内核",
      stat2Val: "一级右键 Bolt ›",
      stat2Lbl: "原生 Finder Sync 扩展直达",
      stat3Val: "4 语种随系统切换",
      stat3Lbl: "简中 · 繁中 · English · 日本語",
      archTitle: "BoltZip 引擎 · 分层架构",
      archLayer1: "macOS 26+ 液态玻璃 · 访达一级 Bolt › 悬浮进度窗 · Quick Look",
      archLayer2: "ZIP64 / 分卷 .z01 / 原地增删改 / WinZip AE-2 / GB18030 自动识别",
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
      statusRight: "macOS 26+ Apple Silicon · Liquid Glass",
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
      f1Desc: "无需全量解压即可浏览目录树、空格键调用 Quick Look 预览、直接拖入新文件进 ZIP、重命名、删除或单独导出选中项——未改动文件零重压缩。",
      f2Title: "自动删除 .DS_Store 等垃圾文件",
      f2Desc: "打包、包内追加与解压时默认自动剔除 <code>.DS_Store</code>、<code>__MACOSX</code> 与 <code>._*</code>，发给 Windows/Linux 同事干干净净。",
      f3Title: "Smart 智能解压",
      f3Desc: "自动判断包内结构：单一根目录直接释放不套娃；多文件散装包自动建立同名子目录。",
      f4Title: "GBK / Shift-JIS 乱码自愈",
      f4Desc: "自动识别 Windows 工具打包的无 UTF-8 标记文件名（GB18030 / Big5 / Shift-JIS / EUC-KR）。",
      f5Title: "WinZip AE-2 AES-256",
      f5Desc: "PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1，与 Windows 7-Zip / WinZip 密码互通。",
      f6Title: "访达右键「Bolt ›」独立悬浮进度窗 & Swift 6 CLI",
      f6Desc: "原生 <code>FinderSync</code> 扩展提供「智能解压 / 压缩 ZIP / TAR.ZST / 7z」快捷动作：点击后仅在屏幕角落弹出轻量化悬浮进度卡片（含实时 ETA、暂停/继续、停止与内联密码解锁），不强行唤起主界面，任务结束自动优雅退出；同步附带 <code>boltzip</code> 命令行工具。",
      f7Title: "Apple Silicon M 系列专属优化（macOS 26.0+）",
      f7Desc: "原生面向 M 系列芯片（<code>arm64</code>）静态编译核心压缩库，零 Homebrew 运行时依赖（Intel / macOS 12–15 见 v0.9.1）。",
      f8Title: "macOS 26+ 原生三层液态玻璃",
      f8Desc: "全面采用 macOS 26 原生 Liquid Glass 架构（涵盖工作台、设置与压缩向导），支持半透明开关与模糊深度自由调节。",
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
      dlTitle: "下载 BoltZip v1.0.0 安装包与源代码",
      dlSub: "Apple Silicon 原生构建（M 系列 arm64 专属，macOS 26.0+），静态链接全部开源压缩库",
      dlAppTag: "macOS App · Apple Silicon",
      dlAppDesc: "包含 BoltZip.app、内置 boltzip CLI 与 FinderSync 右键菜单扩展，开箱即用零外部依赖（Intel / macOS 12–15 见 v0.9.1）。",
      dlAppBtn: "⬇ 下载 App 压缩包 (.zip)",
      dlSrcTag: "MIT 完整源码归档",
      dlSrcTitle: "Source Code v1.0.0",
      dlSrcDesc: "包含完整 SwiftPM 工程源码、C 编解码桥接与 Apple Silicon 打包脚本。",
      dlVerifyTag: "完整性校验",
      dlVerifyTitle: "SHA-256 校验清单",
      dlVerifyDesc: "下载后可执行 shasum -a 256 -c BoltZip-1.0.0-SHA256SUMS.txt 验证包完整性。",
      dlVerifyBtn: "查看 / 下载 SHA256SUMS.txt",
      qsTitle: "从 GitHub 克隆并构建 BoltZip",
      qsSub: "仓库提供完整的 SwiftPM 工程、Apple Silicon 打包脚本以及面向开发者的 AGENTS.md",
      qsStep1: "1. 克隆并打包 BoltZip.app",
      qsStep2: "2. 运行全套单元测试",
      qsStep3: "3. 使用 boltzip CLI",
      copyBtn: "复制",
      copiedBtn: "已复制 ✓",
      copyManualBtn: "请手动复制",
      footerDesc: "<strong>BoltZip v1.0.0</strong> · 面向 macOS 26.0+ & Apple Silicon 的开源液态玻璃压缩工作台"
    },
    "zh-Hant": {
      htmlLang: "zh-TW",
      pageTitle: "BoltZip v1.0.0 — 專為 Apple Silicon & macOS 26+ 打造的開源液態玻璃壓縮工作台",
      navDownload: "下載安裝包",
      navSim: "互動模擬",
      navFeat: "核心功能",
      navAlgo: "開源演算法",
      navBuild: "建置指南",
      navGitHub: "GitHub 專案",
      heroBadge: "macOS 26+ Apple Silicon (arm64) · 原生 Liquid Glass · MIT 開源",
      heroTitle: "<span class=\"gradient-text\">快如閃電，通透如玻</span><br />讓 macOS 壓縮像桌面一樣順手。",
      heroDesc: "告別雙擊就整包解壓一地的困擾。BoltZip 結合純淨開源演算法核心，完整提供「封存檔內建瀏覽、直接增刪修改、自動刪除 .DS_Store、編碼亂碼自動修正、Finder 第一層 Bolt 獨立進度視窗與 macOS 26+ 原生液態玻璃」。",
      heroCtaDownload: "⬇ 下載 v1.0.0 Apple Silicon",
      heroCta1: "▶ 體驗互動模擬器",
      heroCta2: "取得原始碼並建置",
      stat1Val: "6 大開源核心",
      stat2Val: "第一層右鍵 Bolt ›",
      stat2Lbl: "原生 Finder Sync 延伸功能",
      stat3Val: "4 國語言自動切換",
      stat3Lbl: "簡中 · 繁中 · English · 日本語",
      archTitle: "BoltZip 引擎 · 分層架構",
      archLayer1: "macOS 26+ 液態玻璃 · Finder 第一層 Bolt › 懸浮進度窗 · Quick Look",
      archLayer2: "ZIP64 / 分卷 .z01 / 原地增刪修改 / WinZip AE-2 / GB18030 自動偵測",
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
      statusRight: "macOS 26+ Apple Silicon · Liquid Glass",
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
      f1Desc: "免全量解壓即可瀏覽目錄樹、空白鍵呼叫 Quick Look 預覽、直接拖曳新增檔案進 ZIP、重新命名、刪除或單獨匯出選取項目——未異動檔案零重壓縮。",
      f2Title: "自動刪除 .DS_Store 等隱藏垃圾檔案",
      f2Desc: "打包、包內追加與解壓時預設自動過濾 <code>.DS_Store</code>、<code>__MACOSX</code> 與 <code>._*</code>，跨平台分享乾淨清爽。",
      f3Title: "Smart 智慧解壓",
      f3Desc: "自動判斷目錄結構：單一根目錄直接釋放不套娃；多檔案散裝包自動建立同名子資料夾。",
      f4Title: "GBK / Shift-JIS 亂碼自動修正",
      f4Desc: "自動識別 Windows 工具建立的無 UTF-8 標記檔名（GB18030 / Big5 / Shift-JIS / EUC-KR）。",
      f5Title: "WinZip AE-2 AES-256",
      f5Desc: "PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1，與 Windows 7-Zip / WinZip 密碼完全互通。",
      f6Title: "Finder 右鍵「Bolt ›」獨立懸浮進度窗 & Swift 6 CLI",
      f6Desc: "原生 <code>FinderSync</code> 延伸功能提供「智慧解壓 / 壓縮 ZIP / TAR.ZST / 7z」快捷項目：點擊後僅於角落彈出輕量懸浮進度卡片（含即時 ETA、暫停/繼續、停止與內嵌密碼解鎖），不強行喚起主視窗，完成即優雅退出；同時內建 <code>boltzip</code> 命令列工具。",
      f7Title: "Apple Silicon M 系列專屬最佳化（macOS 26.0+）",
      f7Desc: "原生針對 M 系列晶片（<code>arm64</code>）靜態編譯核心壓縮庫，零 Homebrew 執行期相依套件（Intel / macOS 12–15 請見 v0.9.1）。",
      f8Title: "macOS 26+ 原生三層液態玻璃",
      f8Desc: "全面採用 macOS 26 原生 Liquid Glass 架構（含設定與壓縮精靈），支援半透明與模糊深度調節。",
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
      dlTitle: "下載 BoltZip v1.0.0 安裝包與原始碼",
      dlSub: "Apple Silicon 原生執行檔（M 系列 arm64 專屬，macOS 26.0+），靜態連結全套開源壓縮庫",
      dlAppTag: "macOS App · Apple Silicon",
      dlAppDesc: "內含 BoltZip.app、boltzip CLI 與 FinderSync 右鍵選單延伸功能，開箱即用（Intel / macOS 12–15 見 v0.9.1）。",
      dlAppBtn: "⬇ 下載 App 壓縮包 (.zip)",
      dlSrcTag: "MIT 完整原始碼",
      dlSrcTitle: "Source Code v1.0.0",
      dlSrcDesc: "包含完整 SwiftPM 專案、C 橋接程式與 Apple Silicon 打包腳本。",
      dlVerifyTag: "完整性校驗",
      dlVerifyTitle: "SHA-256 雜湊清單",
      dlVerifyDesc: "下載後可透過 shasum -a 256 -c BoltZip-1.0.0-SHA256SUMS.txt 驗證檔案一致性。",
      dlVerifyBtn: "檢視 / 下載 SHA256SUMS.txt",
      qsTitle: "從 GitHub 取得並建置 BoltZip",
      qsSub: "內含完整 SwiftPM 專案、Apple Silicon 打包腳本與開發者指引 AGENTS.md",
      qsStep1: "1. 下載並打包 BoltZip.app",
      qsStep2: "2. 執行完整單元測試",
      qsStep3: "3. 使用 boltzip CLI",
      copyBtn: "複製",
      copiedBtn: "已複製 ✓",
      copyManualBtn: "請手動複製",
      footerDesc: "<strong>BoltZip v1.0.0</strong> · 專為 macOS 26.0+ & Apple Silicon 打造的開源液態玻璃壓縮工作台"
    },
    "en": {
      htmlLang: "en",
      pageTitle: "BoltZip v1.0.0 — Apple Silicon Liquid Glass Archive Studio for macOS 26+",
      navDownload: "Downloads",
      navSim: "Simulator",
      navFeat: "Features",
      navAlgo: "Codecs",
      navBuild: "Build",
      navGitHub: "GitHub Repo",
      heroBadge: "macOS 26+ Apple Silicon (arm64) · Native Liquid Glass · MIT",
      heroTitle: "<span class=\"gradient-text\">Lightning-fast archives.</span><br />Liquid-clear macOS craft.",
      heroDesc: "Stop extracting entire archives just to peek inside. BoltZip pairs open-source codecs (zlib, Zstandard, LZMA2, bzip2, LZ4, libarchive) with in-archive browsing, live ZIP editing, automatic .DS_Store removal, CJK encoding auto-fix, a floating Finder HUD, and native macOS 26+ Liquid Glass (legacy Intel / macOS 12–15: v0.9.1).",
      heroCtaDownload: "⬇ Download v1.0.0 Apple Silicon",
      heroCta1: "▶ Try Interactive Simulator",
      heroCta2: "Clone & Build",
      stat1Val: "6 Open Codecs",
      stat2Val: "Top-Level Bolt ›",
      stat2Lbl: "Native Finder Sync Extension",
      stat3Val: "4 Languages",
      stat3Lbl: "zh-Hans · zh-Hant · EN · JA",
      archTitle: "BoltZip Engine · Layered Architecture",
      archLayer1: "macOS 26+ Native Liquid Glass · Finder Bolt › Floating HUD · Quick Look",
      archLayer2: "ZIP64 / Split .z01 / In-Place Edit / WinZip AE-2 / GB18030 Auto-Detect",
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
      statusRight: "macOS 26+ Apple Silicon · Liquid Glass",
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
      f1Desc: "Browse folder trees without full extraction, press Space for Quick Look, drop files into ZIPs, rename, delete, or export selections — untouched items stay zero-recompress.",
      f2Title: "Auto-Delete .DS_Store & Mac Junk",
      f2Desc: "Automatically strips <code>.DS_Store</code>, <code>__MACOSX</code>, and <code>._*</code> during creation, append, and extraction so archives stay spotless on Windows/Linux.",
      f3Title: "Smart Extraction",
      f3Desc: "Inspects archive layout automatically: single root folder extracts directly; multi-root archives create a clean wrapping subfolder.",
      f4Title: "CJK Mojibake Auto-Repair",
      f4Desc: "Auto-detects legacy codepages (GB18030 / Big5 / Shift-JIS / EUC-KR) for ZIP archives created without UTF-8 flags on Windows.",
      f5Title: "WinZip AE-2 AES-256",
      f5Desc: "PBKDF2-HMAC-SHA1 + AES-256-CTR + 10-byte HMAC-SHA1 authentication, interoperable with Windows 7-Zip and WinZip.",
      f6Title: "Top-Level Finder “Bolt ›” Floating HUD & Swift 6 CLI",
      f6Desc: "Native <code>FinderSync</code> menu launches quick compress/extract in a lightweight floating HUD (live ETA, Pause/Resume, Stop, inline password unlock) without raising the main window, and auto-quits cleanly on close. Ships with <code>boltzip</code> CLI.",
      f7Title: "macOS 26.0+ Apple Silicon Exclusive (arm64)",
      f7Desc: "Zero Homebrew runtime dependencies; statically compiles M-series (<code>arm64</code>) compression libraries (Intel / macOS 12–15: v0.9.1).",
      f8Title: "3-Layer Native Liquid Glass",
      f8Desc: "Full native macOS 26 Liquid Glass across Explorer, Settings, Benchmark, and Compression Wizard with live translucency and blur tuning.",
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
      dlTitle: "Download BoltZip v1.0.0 App & Source Archives",
      dlSub: "Apple Silicon native binary (arm64, macOS 26.0+) with zero Homebrew runtime dependencies",
      dlAppTag: "macOS App · Apple Silicon",
      dlAppDesc: "Includes BoltZip.app, bundled boltzip CLI, and the sandboxed FinderSync right-click extension (Intel / macOS 12–15: v0.9.1).",
      dlAppBtn: "⬇ Download Apple Silicon App (.zip)",
      dlSrcTag: "MIT Source Archives",
      dlSrcTitle: "Source Code v1.0.0",
      dlSrcDesc: "Complete SwiftPM workspace, C codec bridge, tests, and Apple Silicon packager scripts.",
      dlVerifyTag: "Checksums",
      dlVerifyTitle: "SHA-256 Verification",
      dlVerifyDesc: "Run shasum -a 256 -c BoltZip-1.0.0-SHA256SUMS.txt to verify release integrity.",
      dlVerifyBtn: "View / Download SHA256SUMS.txt",
      qsTitle: "Clone & Build BoltZip from GitHub",
      qsSub: "Includes full SwiftPM sources, Apple Silicon app bundler scripts, and AGENTS.md",
      qsStep1: "1. Clone & Package BoltZip.app",
      qsStep2: "2. Run Full Test Suite",
      qsStep3: "3. Use boltzip CLI",
      copyBtn: "Copy",
      copiedBtn: "Copied ✓",
      copyManualBtn: "Copy manually",
      footerDesc: "<strong>BoltZip v1.0.0</strong> · Open-Source Apple Silicon Archive Studio for macOS 26.0+"
    },
    "ja": {
      htmlLang: "ja",
      pageTitle: "BoltZip v1.0.0 — Apple Silicon & macOS 26+ 専用オープンソース書庫ワークベンチ",
      navDownload: "ダウンロード",
      navSim: "シミュレーター",
      navFeat: "主な機能",
      navAlgo: "圧縮エンジン",
      navBuild: "ビルド手順",
      navGitHub: "GitHub",
      heroBadge: "macOS 26+ Apple Silicon (arm64) · ネイティブ Liquid Glass · MIT",
      heroTitle: "<span class=\"gradient-text\">稲妻の速さ、ガラスの透明感</span><br />macOS のための書庫スタジオ。",
      heroDesc: "中身を見るたびに丸ごと展開する必要はありません。BoltZip はオープンソース圧縮基盤に加え、展開不要の閲覧・編集、.DS_Store 自動除去、文字化け補正、Finder 第一階層「Bolt ›」進捗 HUD と macOS 26+ ネイティブ Liquid Glass を提供します（Intel / macOS 12–15 は v0.9.1）。",
      heroCtaDownload: "⬇ v1.0.0 Apple Silicon を入手",
      heroCta1: "▶ インタラクティブ体験",
      heroCta2: "ソースを取得してビルド",
      stat1Val: "6 つの圧縮方式",
      stat2Val: "第一階層 Bolt ›",
      stat2Lbl: "ネイティブ Finder Sync 拡張",
      stat3Val: "4 言語対応",
      stat3Lbl: "簡中 · 繁中 · EN · 日本語",
      archTitle: "BoltZip エンジン · レイヤード構造",
      archLayer1: "macOS 26+ ネイティブ Liquid Glass · Finder Bolt › 進捗 HUD · Quick Look",
      archLayer2: "ZIP64 / 分割 .z01 / 書庫内直接編集 / WinZip AE-2 / 文字コード自動判別",
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
      statusRight: "macOS 26+ Apple Silicon · Liquid Glass",
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
      f1Desc: "全展開せずに階層表示・Quick Look プレビュー・ZIP 内への追加・リネーム・削除・選択書き出しが可能（未変更項目は再圧縮ゼロ）。",
      f2Title: ".DS_Store 等 Mac ゴミファイルを自動削除",
      f2Desc: "圧縮・追記・展開時に <code>.DS_Store</code>、<code>__MACOSX</code>、<code>._*</code> を既定で除外し、Windows/Linux 共有もクリーンに。",
      f3Title: "スマート展開",
      f3Desc: "単一ルートフォルダなら直下にそのまま展開、複数ファイル混在時は自動で同名フォルダを作成して整理します。",
      f4Title: "Shift-JIS / GBK 文字化け自動補正",
      f4Desc: "Windows 製ツールで作られた UTF-8 フラグなし書庫の文字コード（GB18030 / Big5 / Shift-JIS / EUC-KR）を自動判別します。",
      f5Title: "WinZip AE-2 AES-256 暗号化",
      f5Desc: "PBKDF2-HMAC-SHA1 + AES-256-CTR + 10B HMAC-SHA1 に対応し、Windows 版 7-Zip / WinZip と相互運用可能です。",
      f6Title: "Finder 右クリック「Bolt ›」進捗 HUD ＆ Swift 6 CLI",
      f6Desc: "ネイティブ <code>FinderSync</code> 拡張のクイック操作では主画面を開かず画面隅に軽量進捗 HUD（残り時間・一時停止・停止・パスワード入力）のみを表示し、終了時は自動終了します。<code>boltzip</code> CLI も同梱。",
      f7Title: "macOS 26.0+ Apple Silicon 専用（arm64）",
      f7Desc: "Homebrew ランタイム不要。Apple Silicon（<code>arm64</code>）向けに圧縮ライブラリをネイティブ静的リンク（Intel / macOS 12–15 は v0.9.1）。",
      f8Title: "3層ネイティブ Liquid Glass",
      f8Desc: "ワークスペースから設定画面・圧縮ウィザードまで macOS 26 ネイティブ Liquid Glass を適用し、透明度調整にも対応。",
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
      dlTitle: "BoltZip v1.0.0 アプリ & ソースをダウンロード",
      dlSub: "Apple Silicon ネイティブバイナリ（arm64・macOS 26.0+ 専用・外部依存なし）",
      dlAppTag: "macOS アプリ · Apple Silicon",
      dlAppDesc: "BoltZip.app、boltzip CLI、FinderSync 右クリック拡張をすべて同梱しています（Intel / macOS 12–15 は v0.9.1）。",
      dlAppBtn: "⬇ Apple Silicon App をダウンロード (.zip)",
      dlSrcTag: "MIT ソースアーカイブ",
      dlSrcTitle: "Source Code v1.0.0",
      dlSrcDesc: "SwiftPM ソース一式、C ブリッジ、テストと Apple Silicon ビルドスクリプトを含みます。",
      dlVerifyTag: "整合性検証",
      dlVerifyTitle: "SHA-256 チェックサム",
      dlVerifyDesc: "shasum -a 256 -c BoltZip-1.0.0-SHA256SUMS.txt でファイル整合性を検証できます。",
      dlVerifyBtn: "SHA256SUMS.txt をダウンロード",
      qsTitle: "GitHub からクローンしてビルド",
      qsSub: "SwiftPM 構成、Apple Silicon アプリ化スクリプト、開発者向け AGENTS.md を同梱",
      qsStep1: "1. クローン＆BoltZip.app パッケージ化",
      qsStep2: "2. ユニットテストを実行",
      qsStep3: "3. boltzip CLI を使用",
      copyBtn: "コピー",
      copiedBtn: "コピー完了 ✓",
      copyManualBtn: "手動コピー",
      footerDesc: "<strong>BoltZip v1.0.0</strong> · macOS 26.0+ & Apple Silicon 対応オープンソース圧縮ワークベンチ"
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
