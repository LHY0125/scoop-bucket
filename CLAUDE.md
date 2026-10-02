# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库性质

LHY0125 的个人 Scoop bucket（桶名 `lhy`），由 `ScoopInstaller/BucketTemplate` 生成。
**这里没有需要编译的代码** —— 唯一的"产品"是 `bucket/*.json` 清单：每个文件声明一个应用的
下载地址、哈希、可执行文件与自动更新规则。

`bin/` 与 `Scoop-Bucket.Tests.ps1` 是**模板自带**的工具与测试入口，不是本仓库编写的代码，
不要为"改进"而手改；升级来自上游模板。

用户侧用法见 `README.md`：`scoop bucket add lhy https://github.com/LHY0125/scoop-bucket`，
然后 `scoop install lhy/<app>`。桶内同时有自有项目与第三方包，各包遵循各自许可证。

## 三层自动化闭环（理解本仓库的关键）

三件事互相咬合，改任何一环都会影响另两环：

1. **`autoupdate` 块**（在每个清单内）声明如何从上游推断新版本的 URL 与哈希
2. **Excavator**（`.github/workflows/excavator.yml`，每 4 小时）读 `autoupdate` 自动提交版本升级
3. **CI**（`ci.yml`）在每次 push 校验清单合法性 + 仓库文件规范

推论：**清单写得自洽，后续版本升级就全自动**；而 `checkver`/`autoupdate` 写错**不会立刻报错**，
只会让 excavator 静默失效 —— 这是本仓库最容易埋雷的地方。

## 常用命令

```powershell
# 校验单个清单（首选 —— 一次覆盖 CI 会跑的全部检查，退出码 0 = 可提交）
Set-Location 'D:\Code\doing_exercises\programs\scoop-bucket'
& '.\.claude\skills\scoop-bucket\scripts\verify-manifest.ps1' -ManifestPath '.\bucket\<app>.json'
#   加 -SkipNetwork 做离线自检

# 单个清单查上游最新版本（必须传文件路径；见下方"桶副本"提醒）
& .\bin\checkver.ps1 -App (Resolve-Path '.\bucket\<app>.json').Path

# 本地跑 CI 全套（需 Pester 5.2.0 + BuildHelpers；本机通常只有 3.4.0）
.\bin\test.ps1
```

**没有"只跑单个测试"的选择器。** `Scoop-Bucket.Tests.ps1` 只是 import Scoop 的
`test/Import-Bucket-Tests.ps1`，整体执行。要本地复现其中某一项，见下节。

`lhy` 桶在 Scoop 里注册的是 **git 远端**（Scoop 有自己的 clone），所以**未推送的清单
`scoop checkver <app>` 看不到** —— 查清单一律用上面的文件路径形式。

## 文件级规则（CI 对**所有**非二进制文件断言）

`Scoop-00File.Tests.ps1` 逐个检查仓库内每个文件，一条不过整个 CI 就红：

- 行尾 **CRLF**（按 `\r\n` 切分后不得残留孤立 `\r` 或 `\n`）
- 无 UTF-8 BOM、无行尾空格、无 Tab 缩进、必须以换行结尾
- **禁止 0 字节文件** —— 空文件守卫藏在 `file newlines are CRLF` 测试里，失败信息会把人往行尾方向引。`.gitkeep` 一律写说明文字
- `.ps1` 必须无 PowerShell 语法错误 —— 且**字符串字面量必须纯 ASCII**：该测试跑在 Windows PowerShell 5.1 上，用 `Get-Content` 按系统 ANSI 代码页读取，cp1252 下中文/破折号等会被解成智能引号而**截断字符串**（注释里的中文安全）。加 BOM 不行，CI 禁止 BOM

> **`Write` 工具在本仓库会写出 LF**，改完文本文件必须归一化行尾；`Edit` 工具无此问题。

本地复现 Schema 校验**不必装 Pester** —— 用 Scoop 自带的同一个校验器：

```powershell
$sh = (scoop prefix scoop)
Add-Type -Path "$sh\supporting\validator\bin\Scoop.Validator.dll"
$v = New-Object Scoop.Validator("$sh/schema.json", $true)
$v.Validate($path); $v.ErrorsAsString     # 空 = 通过
```

## 清单约定（非显然的部分）

- `hash` 用**裸十六进制**，不带 `sha256:` 前缀 —— Scoop 的 autoupdate 写回时会剥掉前缀。
- 上游把 release 标为 **prerelease** 时，GitHub 的 `/releases/latest` 会 **404**，`checkver`
  必须改用 `/releases` 列表端点取 `$[0].tag_name`。**这类非常规决策要写进清单的 `##` 注释字段**，
  否则后人"顺手优化"回去会让自动更新静默失效。
- `notes` 只支持 `$dir` / `$original_dir` / `$persist_dir` 三个替换变量；`scoop info` 渲染时把
  `$dir` 显示成 `<root>`，所以**光看 `scoop info` 发现不了 notes 里的路径写错**。
- 新增/更新/移除应用的完整流程：`.claude/skills/scoop-bucket/SKILL.md`；
  踩坑清单：同目录 `references/pitfalls.md`（**动清单前必读**）。

## 本机绑定文件与双向 gitignore（容易搞反）

已在 `.gitignore`、**不要提交**（含绝对路径，换机器必然失效）：
`.mcp.json`、`.codex/config.toml`、`.claude/settings.local.json`。

**但方向相反的另一类绝不能 ignore**：`aoci.txt`、`aoci.meta.txt`、`aoci.code.txt`、`AGENTS.md`。
AOCI 的 `scan` 按 **Git 的忽略权威**取文件，被忽略的会**静默跳过** —— 不报错，只是索引建不起来。

## AOCI 认知层

本仓库启用了 AOCI（`aoci.txt` + `.aoci/`）。**`AGENTS.md` 中 `<!-- aoci:begin -->` 到
`<!-- aoci:end -->` 之间是机器托管区块，不要手改**；要更新认知请走 AOCI 的 MCP 工具或 CLI。
认知资产的改动应与业务文件在提交中区分开。

## 需要读多个文件才能明白的布局


| 路径                           | 说明                                                                                                                                          |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `bucket/`                      | 唯一需要日常维护的目录 —— 应用清单                                                                                                          |
| `bin/`                         | BucketTemplate 工具。注意`formatjson` 与 `checkver -Update` 会**就地重写**，对 `bucket/` 整目录跑会连带改掉他人清单 —— 要跑就在临时副本上跑 |
| `scripts/`                     | 供应用安装时使用的辅助文件（模板预建，当前为空）                                                                                              |
| `deprecated/`                  | 存放不再提供安装的历史清单（当前为空）                                                                                                        |
| `.claude/skills/scoop-bucket/` | 本仓库专属的新增/更新/移除流程 + 校验脚本                                                                                                     |
| `.context/`                    | 开发决策审计链；`prefs/` 是本仓库的编码规范与工作流规则                                                                                       |

`.github/workflows/` 除 `ci.yml` 与 `excavator.yml` 外，`issues.yml` 与 `pull_request.yml` 接的是
ScoopInstaller 官方 issue/PR 处理器（可自动修哈希、支持 `/verify` 评论触发）。

## .context 项目上下文

> 项目使用 `.context/` 管理开发决策上下文。

- 编码规范：`.context/prefs/coding-style.md`
- 工作流规则：`.context/prefs/workflow.md`
- 决策历史：`.context/history/commits.md`

**规则**：修改代码前必读 prefs/，做决策时按 workflow.md 规则记录日志。
