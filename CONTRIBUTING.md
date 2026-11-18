# Contributing to BoltZip

感谢你关注并为 **BoltZip** 贡献代码！为保证发布分支稳定与版本演进清晰，请按以下分支规范提交 Pull Request：

## 分支结构与提交流程

| 分支 | 用途 | 规则 |
| :--- | :--- | :--- |
| **`dev-1.0.1`** *(GitHub 默认分支)* | **当前活跃开发分支** | 所有日常功能开发、Bug 修复与文档改进 **均须以本分支作为起点与 PR 目标分支（base）** |
| **`main`** | **稳定发布分支**（受保护） | 禁止直接 `git push`；仅接收维护者从活跃开发分支合入的版本发布 PR |
| **`legacy/macos-12`** | **v0.9.1 LTS 兼容分支** | 仅维护 Intel (`x86_64`) + macOS 12–26 关键兼容性修复 |

> [!IMPORTANT]
> 请不要将常规开发 PR 指向 `main`。在 GitHub 创建 PR 时请确认顶部 `base:` 分支为 **`dev-1.0.1`**（当前默认分支）；针对 `main` 的非发布 PR 会触发 [`pr-target-guard`](.github/workflows/pr-target-guard.yml) 自动提醒并关闭。

## 开发与验证规范

1. 从当前默认分支切出开发分支：
   ```bash
   git clone https://github.com/hwang8859-1/BoltZip.git
   cd BoltZip
   git checkout -b feat/your-change
   ```
2. 提交前请参考 [`AGENTS.md`](AGENTS.md) 中的工程约束并执行完整检查：
   ```bash
   swift test
   ./Scripts/build_app.sh
   codesign --verify --deep --strict dist/BoltZip.app
   ```
3. 请勿硬编码任何本地用户路径（如 `/Users/...`），新增用户界面文案请完整补充 `L10n.swift` 四语支持（`zh-Hans` / `zh-Hant` / `en` / `ja`）。

---

## Branch Workflow (English)

- **`dev-1.0.1`** *(default branch)*: Active development branch. Always fork/branch from it and target **`dev-1.0.1`** as your PR base branch.
- **`main`** *(protected)*: Release-only branch. Direct pushes are blocked, and non-release PRs targeting `main` are rejected automatically.
- **`legacy/macos-12`**: Maintenance branch for macOS 12–26 Universal (`arm64` + `x86_64`) v0.9.x releases.
