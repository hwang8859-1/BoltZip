> [!IMPORTANT]
> **请确认目标分支（Base Branch） / Please check your Target Branch**
>
> - **`main` 分支仅用于稳定版本发布（已受保护）**，不直接接收日常功能或修复 PR。
> - **所有贡献 PR 请务必提交到仓库当前的默认 `dev-*` 开发分支**（打开 PR 时 GitHub 默认选中的 `base:` 分支）。错向 `main` 提交的非发布 PR 将被自动拦截提醒并关闭。
> - *`main` is strictly release-only. Please keep the **base branch** set to the repository's active default **`dev-*`** branch.*

## 变更说明 / Summary

<!-- 请简述本 PR 的改动内容与动机 / Briefly describe what this PR changes and why -->

## 检查清单 / Checklist

- [ ] **目标分支（base）** 已保持为仓库当前默认开发分支 **`dev-*`**（而非 `main`）。
- [ ] 已本地运行 `swift test` 且全部通过。
- [ ] 未在源码、脚本或 `showcase/` 中引入任何本机路径（`/Users/...`）。
- [ ] 若修改 UI 界面文案，已同步更新 `Sources/BoltZipApp/Localization/L10n.swift` 中的四语言翻译（简体中文 / 繁體中文 / English / 日本語）。
- [ ] 若改动核心压缩 / 加密 / 分卷逻辑，已对照 [AGENTS.md](AGENTS.md) 验证所有不变量。
