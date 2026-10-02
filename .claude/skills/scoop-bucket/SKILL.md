---
name: scoop-bucket
description: 维护 LHY0125 个人 Scoop bucket（lhy 桶）清单的规范流程，覆盖新增应用、人工更新版本、移除应用三类操作，含 manifest 撰写要点、checkver/autoupdate 模式选择、哈希三方交叉校验与 CI 规则复现。Use when 用户要求添加应用/新包到 scoop bucket、更新 bucket 中某应用版本、从 bucket 移除应用、编写或修改 scoop manifest，或提到 lhy bucket、scoop-bucket 仓库、checkver、autoupdate、bucket 清单、scoop manifest。
---

# Scoop Bucket 清单维护

| 项 | 值 |
| --- | --- |
| 仓库 | `D:\Code\doing_exercises\programs\scoop-bucket`（桶名 `lhy`，分支 `master`，清单在 `bucket/*.json`） |
| 校验脚本 | `scripts/verify-manifest.ps1`（本 skill 自带） |
| CI | `.github/workflows/ci.yml` → `bin/test.ps1`（Pester，powershell + pwsh 双矩阵） |
| 自动更新 | `.github/workflows/excavator.yml`，每 4 小时自动跟进新版本 |

## 四条铁律

1. **删文件先取得书面同意** —— 用户全局规则。移除应用属于删文件，动手前必须获准。
2. **提交前必跑校验脚本** —— 它一次覆盖 CI 全部检查，不要靠肉眼。
3. **哈希三方交叉校验** —— 本地实测 / 上游 `SHA256SUMS` / GitHub API asset `digest`，三者一致才算过。
4. **别对整个 `bucket/` 目录跑会重写文件的工具** —— `formatjson` 与 `checkver -ForceUpdate` 都是就地重写。

写清单前先扫一遍 [references/pitfalls.md](references/pitfalls.md)，那里是历次踩坑沉淀。

## 流程 A：新增应用

- [ ] A1 调研上游（描述 / 许可证 / release 与 asset 列表）
- [ ] A2 实际下载解压，确认可执行文件在包内的准确名字与层级
- [ ] A3 写清单
- [ ] A4 跑校验脚本，必须 FAIL 0
- [ ] A5 提交推送，确认 CI 绿

### A1 调研

```powershell
gh api repos/<owner>/<repo> --jq '{description, license: .license.spdx_id, homepage}'
gh api repos/<owner>/<repo>/releases --jq '.[0:5][] | {tag_name, prerelease}'
gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'
```

- `/releases/latest` **返回 404 ⇒ 上游全是 prerelease** ⇒ `checkver` 必须改用列表端点取 `$[0].tag_name`。
- `license.spdx_id` 为 `NOASSERTION` 时，读仓库 `LICENSE` 正文首行取 SPDX 标识符（如 `FSL-1.1-MIT`）。

### A2 确认产物结构

**不要凭 asset 名字猜。** 必须下载解压 —— `bin` 字段写错会让安装后的命令找不到。

```powershell
$t = "$env:TEMP\probe"; New-Item -ItemType Directory $t -Force | Out-Null
gh release download <tag> --repo <owner>/<repo> --pattern '<asset>' --dir $t
Expand-Archive "$t\<asset>" "$t\x"
Get-ChildItem "$t\x"
& "$t\x\<exe>" --version        # 版本号应与将写入清单的一致
```

### A3 写清单

参考 `bucket/` 下同类清单，或 `bucket/app-name.json.template`。字段速查见 pitfalls 第二节。

### A4 校验

```powershell
Set-Location 'D:\Code\doing_exercises\programs\scoop-bucket'
& '.\.claude\skills\scoop-bucket\scripts\verify-manifest.ps1' -ManifestPath '.\bucket\<app>.json'
```

覆盖 9 项：schema、必填字段、文件级规则、checkver、URL 可达性、哈希实测、包内 `bin` 目标、`notes` 路径。离线自检加 `-SkipNetwork`。

### A5 提交

```powershell
Set-Location 'D:\Code\doing_exercises\programs\scoop-bucket'
git pull --ff-only                       # 必做，见下方提醒
git add bucket/<app>.json
git commit -m 'feat: add <app> manifest'
git push origin master
$id = gh run list --repo LHY0125/scoop-bucket --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $id --repo LHY0125/scoop-bucket --exit-status
```

> **`git pull --ff-only` 不能省。** excavator 每 4 小时自动提交，本地极易落后，直接 push 会被拒。落后时是纯快进，无冲突风险。

## 流程 B：更新已有应用版本

**通常不需人工介入** —— `autoupdate` 块让 excavator 自动跟版本。先确认：

```powershell
Set-Location 'D:\Code\doing_exercises\programs\scoop-bucket'
git pull --ff-only
gh run list --repo LHY0125/scoop-bucket --limit 5      # 看 Excavator 是否已跟到新版本
```

仅在下列情况人工介入：上游改了 asset 命名、换了下载源、或需调整 `checkver` 策略。

```powershell
# 只针对目标清单强制跑 autoupdate（会就地重写该文件）
& .\bin\checkver.ps1 -App (Resolve-Path '.\bucket\<app>.json').Path -ForceUpdate
```

随后照 A4 校验、A5 提交。**核对 diff 只动了 `version`/`url`/`hash`**，出现其他字段变化要查原因。

## 流程 C：移除应用

1. **先向用户列明要删哪些文件并取得明确同意** —— 全局规则硬性要求，不得跳过。
2. 获准后 `git rm bucket/<app>.json`。
3. 评估是否移入 `deprecated/`（该目录已存在，用于保留历史清单）。
4. 照 A5 提交推送。
