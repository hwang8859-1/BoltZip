(() => {
  const initialEntries = [
    { id: "src/", parent: "", name: "src", isDir: true, size: 0, packed: 0, method: "Folder", status: "目录正常", crc: "—" },
    { id: "docs/", parent: "", name: "docs", isDir: true, size: 0, packed: 0, method: "Folder", status: "目录正常", crc: "—" },
    {
      id: "财务报表_2026Q4.xlsx",
      parent: "",
      name: "财务报表_2026Q4.xlsx",
      garbledName: "²ÆÎñ±¨±í_2026Q4.xlsx",
      isDir: false,
      size: 1843200,
      packed: 492100,
      method: "DEFLATE",
      status: "AES-256",
      crc: "AE-2 HMAC"
    },
    {
      id: "交付说明与环境配置.pdf",
      parent: "",
      name: "交付说明与环境配置.pdf",
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
    { id: "docs/架构设计图.png", parent: "docs/", name: "架构设计图.png", garbledName: "¼Ü¹¹Éè¼ÆÍ¼.png", isDir: false, size: 2560000, packed: 2480000, method: "Store", status: "CRC32 OK", crc: "0xE71022A1" }
  ];

  let entries = structuredClone(initialEntries);
  let currentFolder = "";
  let selectedId = "财务报表_2026Q4.xlsx";
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
    const folders = [{ path: "", label: "📦 根目录 (Archive)" }];
    entries.filter(e => e.isDir).forEach(d => {
      folders.push({ path: d.id, label: "📁 " + d.name });
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
    crumbsEl.innerHTML = "";
    const rootBtn = document.createElement("button");
    rootBtn.className = "crumb" + (currentFolder === "" ? " active" : "");
    rootBtn.textContent = "📦 根目录";
    rootBtn.onclick = () => { currentFolder = ""; renderAll(); };
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
        <td>${e.isDir ? "文件夹" : fmtSize(e.size)}</td>
        <td>${e.isDir ? "—" : fmtSize(e.packed)}</td>
        <td>${ratio === "—" ? "—" : `<span class="ratio-badge">${ratio}</span>`}</td>
        <td>${e.method}</td>
        <td><span class="${badgeClass}">${e.status}</span></td>
      `;

      tr.onclick = () => {
        selectedId = e.id;
        statusLeft.textContent = `已选中：${displayName(e)} · ${e.isDir ? "文件夹" : fmtSize(e.size) + " · 校验 " + e.crc}`;
        renderTable();
      };

      tr.ondblclick = () => {
        if (e.isDir) {
          currentFolder = e.id;
          selectedId = null;
          renderAll();
        } else {
          showToast(`👁 <strong>Quick Look 快速预览</strong>：已从内存解密/解码 <code>${displayName(e)}</code>（无需解压整个压缩包）。`);
        }
      };

      tableBody.appendChild(tr);
    });
  }

  function renderAll() {
    renderTree();
    renderBreadcrumbs();
    renderTable();
  }

  document.getElementById("btnExtractSmart").onclick = () => {
    showToast(`📂 <strong>智能解压预览</strong>：检测到压缩包根目录含多个条目，将自动释放到 <code>~/Downloads/2026_华东交付包_v2/</code>，并剔除 Mac 隐藏文件。`);
  };

  let addCounter = 1;
  document.getElementById("btnAddSimFile").onclick = () => {
    const newName = `新增说明_${addCounter++}.txt`;
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
    showToast(`➕ <strong>包内原地添加成功</strong>：已将 <code>${newName}</code> 写入归档，原有文件未发生重压缩。`);
  };

  document.getElementById("btnDeleteSimFile").onclick = () => {
    if (!selectedId) {
      showToast("⚠️ 请先在右侧列表中单击选中一个文件或目录。");
      return;
    }
    const target = entries.find(e => e.id === selectedId);
    if (!target) return;
    entries = entries.filter(e => e.id !== target.id && e.parent !== target.id);
    selectedId = null;
    renderAll();
    showToast(`🗑 已从归档移除 <code>${displayName(target)}</code> 并重建中央目录。`);
  };

  document.getElementById("btnTestIntegrity").onclick = () => {
    const files = entries.filter(e => !e.isDir).length;
    showToast(`🛡 <strong>完整性校验通过</strong>：已验证 ${files} 个条目（CRC32 + WinZip AE-2 HMAC-SHA1），0 个损坏。`);
  };

  function setGBKMode(garbled) {
    gbkGarbledMode = garbled;
    encodingSelect.value = garbled ? "cp437" : "auto";
    gbkBtnText.textContent = garbled ? "✨ 一键智能修复 GBK 乱码" : "模拟 Windows GBK 乱码";
    renderAll();
  }

  document.getElementById("btnToggleGBK").onclick = () => {
    setGBKMode(!gbkGarbledMode);
    if (gbkGarbledMode) {
      showToast(`⚠️ 已切换至未纠偏原始字节：Windows 压缩包中的中文变成了乱码，点击按钮体验自动修复！`);
    } else {
      showToast(`✨ <strong>GB18030 / CP936 自动识别生效</strong>：中文文件名已无损还原！`);
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
  const workloads = {
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
  };

  const algoRowsEl = document.getElementById("algoRows");
  function renderAlgorithms(kind) {
    const items = workloads[kind] || workloads.code;
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
          <div class="metric-label"><span>压缩率表现</span><strong>${item.ratioText}</strong></div>
          <div class="bar-track"><div class="bar-fill bar-ratio" style="width:${item.ratio}%"></div></div>
        </div>
        <div class="metric-bar-group">
          <div class="metric-label"><span>吞吐速度倾向</span><strong>${item.speedText}</strong></div>
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
      try {
        await navigator.clipboard.writeText(txt);
        const orig = btn.textContent;
        btn.textContent = "已复制 ✓";
        setTimeout(() => (btn.textContent = orig), 1600);
      } catch {
        btn.textContent = "请手动复制";
      }
    };
  });

  renderAll();
  renderAlgorithms("code");
})();
