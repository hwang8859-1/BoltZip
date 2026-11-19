# Contributing to BoltZip

感谢你关注并为 **BoltZip** 贡献代码！BoltZip 采用「一版本一活跃 `dev-*` 分支 + 受保护 `main` 发布分支 + `legacy/macos-12` 长期兼容分支」三轨模式（Option A）。

## 分支结构与提交流程

| 分支 | 用途 | 保护与协作规则 |
| :--- | :--- | :--- |
| **[默认 `dev-*` 分支](../../)** *(当前 `dev-1.0.3`)* | **当前活跃开发分支** | 所有日常开发与外部贡献 PR **均须基于并提交至此默认分支**；受 Ruleset 保护禁止强推与误删 |
| **已归档 `dev-*` 分支** | **历史版本只读归档** | 发布后永久保留，**禁止提交、推送、合并与删除**；旧版本修复请走当前活跃分支并随下一版本发布 |
| **`main`** | **稳定发布分支**（受保护） | 禁止直接 `git push`；仅接收从活跃 `dev-*` 合入的版本发布 PR，受 [`pr-target-guard`](.github/workflows/pr-target-guard.yml) 强校验 |
| **`legacy/macos-12`** | **v0.9.3 LTS 兼容分支** | 仅维护 Intel (`x86_64`) + macOS 12–26 关键兼容性修复；受 Ruleset 保护禁止强推与删除 |

> [!IMPORTANT]
> 请不要将常规开发 PR 指向 `main`。由于当前默认分支已设置为活跃 `dev-*` 分支，直接执行 `git clone` 或在 GitHub 点击创建 PR 时会自动指向正确分支；若错指 `main`，[`pr-target-guard`](.github/workflows/pr-target-guard.yml) 会自动提示改投并关闭该 PR。

## 贡献与验证步骤

1. 从当前默认开发分支切出特性分支：
   ```bash
   git clone https://github.com/hwang8859-1/BoltZip.git
   cd BoltZip
   git checkout -b feat/your-change
   ```
2. 提交前请遵守 [`AGENTS.md`](AGENTS.md) 中的开发规范并运行验证：
   ```bash
   swift test
   ./Scripts/build_app.sh --app-only --no-register
   codesign --verify --deep --strict dist/BoltZip.app
   ```
3. 请勿引入本地个人路径（`/Users/...`），新增用户界面文案请完整补充 `L10n.swift` 四语支持（`zh-Hans` / `zh-Hant` / `en` / `ja`）。

## 维护者发版切分支流程

版本发布完成（通过 Merge Commit 将活跃 `dev-*` 合入 `main` 并创建 `vX.Y.Z` Tag）后，运行脚本切换至下一版本分支，**旧分支保留为只读归档**：

```bash
./Scripts/cut_next_dev_branch.sh dev-1.0.4
```

脚本会在任何分支操作前拒绝 `--cleanup-old`。发布后的旧 `dev-*` 分支必须原样保留，并立即在 GitHub `Settings → Rules` 中为其设置 `Restrict updates` 与 `Restrict deletions`；任何修复只能进入当前活跃分支并随下一版本发布。

---

## Branch Workflow (English)

- **[Default `dev-*` branch](../../)** *(currently `dev-1.0.3`)*: Active development branch. Always branch from it and target it as your PR base branch (protected against force pushes and deletion via repository rulesets).
- **Archived `dev-*` branches**: Released `dev-X.Y.Z` branches are kept permanently as read-only archives. Never commit, push, merge, or delete them; fixes belong to the active `dev-*` branch and the next release.
- **`main`** *(protected)*: Release-only branch. Direct pushes are blocked. Release PRs must come from the same repository's active development branch or a designated `release/X.Y.Z-hotfix` branch. Other PRs targeting `main` are closed by [`pr-target-guard`](.github/workflows/pr-target-guard.yml).
- **`legacy/macos-12`**: Maintenance branch for macOS 12–26 Universal (`arm64` + `x86_64`) v0.9.x releases.
