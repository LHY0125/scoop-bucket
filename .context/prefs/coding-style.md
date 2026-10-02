# Coding Style Guide

> 此文件定义本仓库（LHY0125 个人 Scoop bucket）的规范，所有 LLM 工具在修改时必须遵守。
> 提交到 Git。

## General
- Prefer small, reviewable changes; avoid unrelated refactors.
- Name things explicitly; no single-letter variables except loop counters.
- Handle errors explicitly; never swallow errors silently.
- 注释与对话用中文。

## 文件级硬约束（CI 会检查所有非二进制文件）

`Scoop-00File.Tests.ps1` 对仓库内**所有**非二进制文件断言，一条不过就红：

- **行尾必须 CRLF** —— `.gitattributes` 钉了 `eol=crlf`，检出时会转换；但工作区也应保持 CRLF（`.editorconfig` 要求）
- **禁止 UTF-8 BOM**
- **必须以换行结尾**
- **禁止行尾空格**
- **禁止 Tab 缩进**（只用空格）
- **`.ps1` 文件必须无 PowerShell 语法错误**（CI 用 `PSParser::Tokenize` 做词法检查，跑在 **Windows PowerShell 5.1** 上）
- **禁止 0 字节文件** —— CI 的空文件守卫藏在 `file newlines are CRLF` 测试里，失败信息极具误导性。`.gitkeep` 一律写说明文字（照 `scripts/`、`deprecated/` 的既有做法）

> `Write` 工具在本仓库会写出 **LF** —— 用它改完文本文件必须跑一次行尾归一化。
> `Edit` 工具无此问题（字符串替换，保留原行尾）。

归一化写法：

```powershell
$t = [System.IO.File]::ReadAllText($f)
[System.IO.File]::WriteAllText($f, ($t -replace "`r`n","`n" -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
```

## JSON 清单（`bucket/*.json`）

- 4 空格缩进；键序与同类清单保持一致。
- `version` 去掉 tag 的 `v` 前缀。
- `hash` 用**裸十六进制**，不带 `sha256:` 前缀 —— `autoupdate` 写回时会剥掉前缀，保持一致可避免无意义 diff。
- 非常规决策写进 `##` 注释字段（例如「上游全是 prerelease，故 checkver 用列表端点」），否则后人"顺手优化"会把自动更新搞挂。
- **改完必须跑 `.claude/skills/scoop-bucket/scripts/verify-manifest.ps1`，FAIL 0 才提交。**
- 详细踩坑见 `.claude/skills/scoop-bucket/references/pitfalls.md`。

## PowerShell 脚本

- 中文注释；开头 `$ErrorActionPreference = 'Stop'`。
- **字符串字面量必须纯 ASCII**（含哈希键名与输出文案）。原因：CI 的 5.1 用 `Get-Content` 按系统 ANSI 代码页读无 BOM 的 UTF-8，cp1252 下字节 `0x91`–`0x94` 会解成 `' ' " "` 智能引号，而 PowerShell 认它们是引号 → 字符串提前终止 → 报一堆 `Unexpected token`。约 6% 的常用汉字命中该区间，属概率性必炸。
  **注释里的中文是安全的**；不要用加 BOM 绕过（CI 禁止 BOM）。
  排查方式见 `.claude/skills/scoop-bucket/references/pitfalls.md` 3.4（按 cp1252/936/437 显式解码后词法分析，三种都须为 0）。
- **不要解析 Scoop `bin/*.ps1` 的控制台输出** —— 它们用 `Write-Host`（走信息流 6，`2>&1` 抓不到），且多次 `-NoNewline` 会让每个片段各成一行、连 `[2][2][0]` 里的数字都被换行拆开。应改为自行发请求，或读退出码。
- 需要捕获 `Write-Host` 输出时用 `6>&1`。

## Git Commits

- Conventional Commits，祈使句。本仓库常用 `feat:` / `fix:` / `docs:` / `chore:`。
- 原子提交：一次提交一个逻辑变更。
- **push 前必须 `git pull --ff-only`** —— excavator 每 4 小时自动提交一次，本地极易落后，直接 push 会被拒。落后时是纯快进，无冲突风险。

## 安全

- 不提交本机绑定配置（`.mcp.json`、`.codex/config.toml` 已在 `.gitignore`）。
- **未经用户明确书面同意不得删除任何文件**（用户全局规则）。移除应用清单前必须先取得许可。
- 不对整个 `bucket/` 目录跑 `formatjson` 或 `checkver -Update` —— 它们会**就地重写**，会连带改掉他人清单。要跑就在临时副本上跑。

## 验证纪律

- **只写会 PASS 的检查等于没有检查。** 新增校验逻辑后必须做反向测试：故意注入错误（坏 URL、缺字段、转成 LF），确认它真的会 FAIL。
- 碰到不确定的行为，**在实际目标上验证**；不要从单一样本外推"必然/永远不会"。空仓库的样本回答得了"会发生什么"，回答不了"什么时候不发生"。
- 配置类文件要**照它执行一次**来验证，不要只读内容 —— 读文件发现不了引号转义、参数顺序、路径拼接错误。
