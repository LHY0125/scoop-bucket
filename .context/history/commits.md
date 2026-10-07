# Commit Decision History

> 此文件是 `commits.jsonl` 的人类可读视图，可由工具重生成。
> Canonical store: `commits.jsonl` (JSONL, append-only)

| Date | Context-Id | Commit | Summary | Decisions | Bugs | Risk |
|------|-----------|--------|---------|-----------|------|------|
| 2026-10-07 | — | `c3ff6e2` | feat: 添加 agency-agents-app 清单（便携版） | 用 `pre_install`+7-Zip 解包，而非 NSIS 安装器；排除 `$PLUGINSDIR`/`$TEMP` | — | 上游若改发便携 zip 或改用 InnoSetup，需重写该块 |
| 2026-10-07 | — | `a9c1791` | fix: 修正 verify-manifest.ps1 的哈希计算与解压方式 | `Get-FileHash` → .NET `SHA256`；`Expand-Archive` → 7-Zip | 5.1 下 `Get-FileHash` 因 `PSModulePath` 顺序不可用；步骤 8 异常被错误归因到步骤 7 | 低 |
