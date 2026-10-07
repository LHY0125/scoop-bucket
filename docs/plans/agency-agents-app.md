# 计划：为 agency-agents-app 添加 Scoop 清单（便携版）

> 状态：**已执行完成（A1–A4 全部通过）**，待提交
> 起草日期：2026-10-07
> 执行日期：2026-10-07
> 目标仓库：`D:\Code\doing_exercises\programs\scoop-bucket`（桶名 `lhy`，分支 `master`）
> 产出：`bucket/agency-agents-app.json`

## 执行结果摘要（2026-10-07）


| 步骤            | 结果                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| A1 调研         | ✅ 完成                                                                                               |
| A2 实测解压方案 | ✅ 完成，**方案①（`pre_install` + 7z）验证可行**                                                     |
| A3 写清单       | ✅`bucket/agency-agents-app.json`                                                                     |
| A4 校验         | ✅`verify-manifest.ps1` **FAIL 0**                                                                    |
| A4.2 反向测试   | ✅ 三个坏样本全部正确 FAIL                                                                            |
| A4.3 实机安装   | ✅`scoop install` 成功，`pre_install` 生效，shim/快捷方式生成，应用可启动（窗口标题 `Agency Agents`） |
| A4.4 卸载       | ✅ 干净，无残留目录 / shim / 快捷方式 / 注册表项                                                      |
| autoupdate 幂等 | ✅`checkver -App <path> -ForceUpdate` 重写后 `git diff` 为空                                          |

### 执行中发现的三处偏差（均已处理）

1. **`-Switches` 是单个字符串，不是数组**
   计划草案里写的是 `-Switches '-xr!$PLUGINSDIR' '-xr!$TEMP'`（两个参数），实测报
   `A positional parameter cannot be found that accepts argument '-xr!$TEMP'`。
   正确写法是**一个字符串、空格分隔**：`-Switches '-xr!$PLUGINSDIR -xr!$TEMP'`
   （函数内部会 `-split`）。
2. **校验脚本 `verify-manifest.ps1` 有两个既有缺陷**（与本次清单无关，但会拦住所有清单）

   - **步骤 7 用了 `Get-FileHash`，在本机 Windows PowerShell 5.1 下不可用**。
     根因：`PSModulePath` 把 pwsh 7 的 `Modules` 目录排在 5.1 之前，5.1 静默加载不兼容的
     `Microsoft.PowerShell.Utility 7.0.0.0`，`Import-Module` 不报错但命令仍不可用。
     **修法**：改用 `.NET` 的 `SHA256` 直接算（新增 `Get-Sha256` 辅助函数），不依赖模块自动加载。
   - **步骤 8 用了 `Expand-Archive`（只认 zip）**，遇到 NSIS 安装器 / `.7z` / `.tar.gz` 会抛异常，
     且该异常被外层 `catch` 捕获后**错误地记到步骤 7 名下**，报告显示 `[FAIL] 7. Hash check`
     而哈希其实是 OK 的。**修法**：改用 7-Zip 解压（与 Scoop 自身解压器一致），
     并自行定位 `7z.exe`（不调用 Scoop 的 `Get-HelperPath`，本脚本不加载 Scoop 的 lib）。
   - 顺带把 `$scoopHome` 从步骤 3 的 `try` 块提到顶层，供步骤 3/8 共用。
3. **`SKILL.md` 在本次工作开始前（18:25）已被改动**（Markdown 表格分隔行对齐 + 一个空行），
   **不是本次工作产生的**。提交时需与本次清单变更分开处理。

---

## 一、目标与范围

把 `msitarzewski/agency-agents-app` 的**桌面应用**以**便携版（portable）**形式加入 `lhy` 桶。

**明确不在范围内**：

- `msitarzewski/agency-agents`（用户最初给的链接）—— 那是**内容仓库**，0 个 release、无 tag，
  交付物是 Markdown 人设 + 一个 1801 行的 Bash 安装脚本。**无法打包**，本计划不涉及。
- 不修改 `bin/`、`Scoop-Bucket.Tests.ps1`（模板自带，升级来自上游）。
- 不删除任何既有清单。

---

## 二、上游事实（已实测，2026-10-07）

### 2.1 仓库


| 项     | 值                                                     |
| -------- | -------------------------------------------------------- |
| 仓库   | `msitarzewski/agency-agents-app`                       |
| 描述   | 浏览 / 安装 / 跟踪 agency-agents 人设的 Tauri 桌面应用 |
| 语言   | TypeScript（Tauri 2 + Svelte 5 前端，Rust 后端）       |
| 许可证 | **MIT**（`Copyright (c) 2026 Michael Sitarzewski`）    |
| 最新版 | **v0.3.2**（2026-10-03），**非 prerelease**            |
| 官网   | https://agencyagents.app                               |

### 2.2 Release 产物（v0.3.2，共 9 个）


| 平台        | 产物                                                                                | 用途           |
| ------------- | ------------------------------------------------------------------------------------- | ---------------- |
| **Windows** | `Agency_Agents_0.3.2_x64-setup.exe`（8,371,637 B）                                  | **本计划目标** |
| **Windows** | `Agency_Agents_0.3.2_arm64-setup.exe`（7,879,175 B）                                | arm64 备用     |
| macOS       | `..._x64.dmg` / `..._aarch64.dmg` / `..._x64.app.tar.gz` / `..._aarch64.app.tar.gz` | 不涉及         |
| Linux       | `..._amd64.AppImage` / `.deb` / `.rpm`                                              | 不涉及         |

> ⚠️ **`.app.tar.gz` 是 macOS 产物**（`.app` 为 macOS bundle），不是 Windows 便携包。
> Windows 侧**只有 NSIS 安装器**，没有官方 portable zip。

### 2.3 产物实测结论


| 检查项          | 结果                                                                                                                                    |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 文件类型        | `PE32 ... Nullsoft Installer self-extracting archive`（**NSIS-3 Unicode**，LZMA:23 solid）                                              |
| sha256          | `685c80817f67735f8163b290628134b98cb615b065934daed2aa6faaec76a811`（与 API `digest` 一致）                                              |
| `7z x` 提取     | ✅ 成功                                                                                                                                 |
| 提取后布局      | `agency-agents-app.exe`（19 MB，根级）、`resources/corpus-baseline/`（4.7 MB）、`Assets.car`、`uninstall.exe`、`$PLUGINSDIR/`、`$TEMP/` |
| **便携运行**    | ✅**提取后直接 `Start-Process` 成功**，进程 `agency-agents-app` 存活不退出                                                              |
| 静默安装        | ✅`/S /D=<路径>` 有效（本计划**不采用**，仅记录）                                                                                       |
| 依赖            | Tauri → 需 WebView2 Runtime；本机已有（154.0.4258.53）                                                                                 |
| checkver        | ✅`/releases/latest` 返回 `v0.3.2`（**不是**全 prerelease，无 aoci 那个坑）                                                             |
| autoupdate 哈希 | ✅ asset 带`digest` 字段，jsonpath filter 可用                                                                                          |

---

## 三、关键技术约束（决定清单写法）

### 3.1 ⚠️ Scoop **不会**自动解压 `.exe` —— 必须显式指定解压方式

这是本计划最核心的发现，来自读源码：

`lib/decompress.ps1:22-50` 的 `switch -regex ($Name[$i])` 分派：

```powershell
'\.zip$' { $extractFn = 'Expand-7zipArchive' }   # 或 Expand-ZipArchive
'\.msi$' { $extractFn = 'Expand-MsiArchive' }
'\.exe$' { if ($Manifest.innosetup) { $extractFn = 'Expand-InnoArchive' } ; continue }
{ Test-7zipRequirement -Uri $_ } { $extractFn = 'Expand-7zipArchive' }
```

- `.exe` 分支**只在 `innosetup` 为真时**才解压，且只走 InnoSetup 解压器
- 兜底的 `Test-7zipRequirement`（`lib/depends.ps1:134-146`）正则**不匹配 `.exe`**：

  ```
  \.(001|7z|bz(ip)?2?|gz|img|iso|lzma|lzh|nupkg|rar|tar|t[abgpx]z2?|t?zst|xz)(\.[^\d.]+)?$
  ```

  实测：`Agency_Agents_0.3.2_x64-setup.exe` → `7zip-requirement=False`

**结论**：直接写 `"url": "...setup.exe"` + `"bin"` 会**失败** —— Scoop 会把 8.4 MB 的安装器
原样丢进 `apps\agency-agents-app\current\`，然后找不到 `bin` 指向的 exe。

**对策（三选一）**：


| 方案                               | 做法                                          | 评价                                                     |
| ------------------------------------ | ----------------------------------------------- | ---------------------------------------------------------- |
| **① `pre_install` + 7z 显式解压** | 清单内用`Expand-7zipArchive` 解压 `setup.exe` | ✅**采用**                                               |
| ②`"installer"` + NSIS `/S /D=`    | 跑官方安装器                                  | ❌ 写注册表，Scoop 卸载不彻底，违背便携初衷              |
| ③ 依赖`innosetup` 字段            | 设`"innosetup": true`                         | ❌**类型不符**，本产物是 NSIS 不是 InnoSetup，会解压失败 |

### 3.2 Scoop 的 7z 调用会排除两个目录

`lib/decompress.ps1:94`：

```powershell
$ArgList = @('x', $Path, "-o$DestinationPath", '-xr!*.nsis', '-y')
```

注意：源码里**只有 `-xr!*.nsis` 一条排除**（网上流传的"排除 `$PLUGINSDIR`/`$TEMP`"说法
在本机这份 Scoop 上**不成立**）。因此 `pre_install` 里自行调 7z 时，需**自己加排除**，
否则 `$PLUGINSDIR\`（含 `System.dll`、`modern-wizard.bmp` 等）与 `$TEMP\MicrosoftEdgeWebview2Setup.exe`
（1.8 MB）会污染安装目录。

### 3.3 `extract_dir` 与 `-ir!` 的交互

`lib/decompress.ps1:96-98`：

```powershell
if (!$IsTar -and $ExtractDir) { $ArgList += "-ir!$ExtractDir\*" }
```

即 `extract_dir` 会被转成 7z 的 `-ir!<dir>\*` 包含过滤。本产物解压后**目标 exe 在根级**，
所以**不需要 `extract_dir`**（留空即可）。

### 3.4 已知的"脏文件"

解压后除应用本体外还有：

- `uninstall.exe`（83 KB）—— 便携安装用不到，**不写进 `bin`**
- `Assets.car`（1.5 MB）—— macOS 资源，Windows 下无用，但**保留**（删文件需用户同意，且无害）
- `$PLUGINSDIR/`、`$TEMP/` —— 由 3.2 的排除规则处理

---

## 四、拟写清单（草案）

```json
{
    "version": "0.3.2",
    "description": "Desktop app for browsing, installing and tracking the agency-agents persona roster across AI coding tools",
    "homepage": "https://agencyagents.app",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/msitarzewski/agency-agents-app/releases/download/v0.3.2/Agency_Agents_0.3.2_x64-setup.exe",
            "hash": "685c80817f67735f8163b290628134b98cb615b065934daed2aa6faaec76a811"
        },
        "arm64": {
            "url": "https://github.com/msitarzewski/agency-agents-app/releases/download/v0.3.2/Agency_Agents_0.3.2_arm64-setup.exe",
            "hash": "36517de4b4076ac215ea294845fe8dc5cfbd9f9b18be7166fdb609b82b02e58c"
        }
    },
    "pre_install": [
        "$dir = $dir.TrimEnd('\\')",
        "Get-ChildItem -LiteralPath $dir -Filter '*.exe' | Remove-Item -Force -ErrorAction SilentlyContinue",
        "Expand-7zipArchive -Path \"$dir\\Agency_Agents_$version`_x64-setup.exe\" -DestinationPath $dir -Removal"
    ],
    "bin": "agency-agents-app.exe",
    "shortcuts": [
        [
            "agency-agents-app.exe",
            "Agency Agents"
        ]
    ],
    "checkver": {
        "url": "https://api.github.com/repos/msitarzewski/agency-agents-app/releases/latest",
        "jsonpath": "$.tag_name",
        "regex": "v?([\\d.]+(?:-[0-9A-Za-z.-]+)?)"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/msitarzewski/agency-agents-app/releases/download/v$version/Agency_Agents_$version_x64-setup.exe",
                "hash": {
                    "url": "https://api.github.com/repos/msitarzewski/agency-agents-app/releases/tags/v$version",
                    "jsonpath": "$.assets[?(@.name == 'Agency_Agents_$version_x64-setup.exe')].digest"
                }
            },
            "arm64": {
                "url": "https://github.com/msitarzewski/agency-agents-app/releases/download/v$version/Agency_Agents_$version_arm64-setup.exe",
                "hash": {
                    "url": "https://api.github.com/repos/msitarzewski/agency-agents-app/releases/tags/v$version",
                    "jsonpath": "$.assets[?(@.name == 'Agency_Agents_$version_arm64-setup.exe')].digest"
                }
            }
        }
    }
}
```

> ⚠️ **草案未定稿**。`pre_install` 的具体写法需在 A2 阶段实测确认（见第五节），
> 尤其是：`Expand-7zipArchive` 在 `pre_install` 中是否可直接调用、`$version` 变量是否可用、
> 以及排除 `$PLUGINSDIR`/`$TEMP` 的正确开关。**不要照抄草案直接提交。**

---

## 五、执行步骤

### A1 调研（已完成）

见第二节。**无需重复。**

### A2 实测解压方案（**关键，不可跳过**）

- [ ]  A2.1 下载 x64 安装器到临时目录，校验 sha256 与清单声明一致
- [ ]  A2.2 在**临时副本**上试跑 `pre_install` 逻辑，确认：
  - `Expand-7zipArchive` 能否在 `pre_install` 上下文调用（需 `$env:SCOOP_HOME` / 已加载 `lib`）
  - `$version`、`$dir` 变量在 `pre_install` 中的可用性
  - 排除 `$PLUGINSDIR`/`$TEMP` 的开关写法（`-Switches '-xr!$PLUGINSDIR' -xr!$TEMP'`）
- [ ]  A2.3 确认解压后 `agency-agents-app.exe` 位于根级，且能启动
- [ ]  A2.4 **确认 `bin` 指向正确** —— 这是最容易写错、且安装后才暴露的字段

> **若 `pre_install` 方案在实测中受阻**，回退方案：
> 用 `"installer": { "script": [...] }` 跑 NSIS 静默安装（已实测 `/S /D=` 可用），
> 但需在计划中记录"会写注册表"这一代价。

### A3 写清单

- [ ]  A3.1 按 A2 实测结果定稿 `bucket/agency-agents-app.json`
- [ ]  A3.2 4 空格缩进，键序对齐 `bucket/patheditor-gui.json`
- [ ]  A3.3 `hash` 用**裸十六进制**（不带 `sha256:`）
- [ ]  A3.4 若采用非常规解压方式，**在 `##` 字段写明原因**（否则后人会"顺手优化"搞挂）
- [ ]  A3.5 **确保文件行尾为 CRLF**（`Write` 工具会写 LF，需归一化）

### A4 校验

- [ ]  A4.1 跑校验脚本，**必须 FAIL 0**：

  ```powershell
  Set-Location 'D:\Code\doing_exercises\programs\scoop-bucket'
  & '.\.claude\skills\scoop-bucket\scripts\verify-manifest.ps1' -ManifestPath '.\bucket\agency-agents-app.json'
  ```
- [ ]  A4.2 **反向测试**：故意改坏一处（如改错 hash），确认脚本真的会 FAIL
- [ ]  A4.3 **实机安装验证**（`verify-manifest.ps1` 覆盖不到 `pre_install` 的实际执行）：

  ```powershell
  scoop install .\bucket\agency-agents-app.json   # 或先 bucket add 本地路径
  scoop list agency-agents-app
  Test-Path "$(scoop prefix agency-agents-app)\agency-agents-app.exe"
  ```
- [ ]  A4.4 确认 `scoop uninstall` 干净（无残留目录、无注册表项）

### A5 提交推送

- [ ]  A5.1 `git pull --ff-only`（**不可省**，excavator 每 4 小时自动提交）
- [ ]  A5.2 `git add bucket/agency-agents-app.json`（**只加这一个文件**）
- [ ]  A5.3 `git commit -m 'feat: add agency-agents-app manifest'`（中文提交信息，见下）
- [ ]  A5.4 `git push origin master`
- [ ]  A5.5 等 CI 绿：

  ```powershell
  $id = gh run list --repo LHY0125/scoop-bucket --limit 1 --json databaseId --jq '.[0].databaseId'
  gh run watch $id --repo LHY0125/scoop-bucket --exit-status
  ```

### A6 文档同步

- [ ]  A6.1 更新 `README.md` 的清单表格与用法段
- [ ]  A6.2 按 `.context/prefs/workflow.md` 规则，把本次**方案选择**追加到
  `.context/current/branches/master/session.log`
- [ ]  A6.3 若 A2 发现了新坑，追加到 `.claude/skills/scoop-bucket/references/pitfalls.md`

---

## 六、风险与对策


| 风险                                          | 概率 | 影响 | 对策                                                                           |
| ----------------------------------------------- | ------ | ------ | -------------------------------------------------------------------------------- |
| `pre_install` 中无法调用 `Expand-7zipArchive` | 中   | 高   | A2 实测；受阻则回退`installer` 方案                                            |
| 解压后 exe 不在根级 / 名字与预期不符          | 低   | 高   | A2.3 实测确认（已初步验证在根级）                                              |
| `$PLUGINSDIR`/`$TEMP` 污染安装目录            | 中   | 中   | A2.2 确认排除开关                                                              |
| 上游改 asset 命名导致 autoupdate 失效         | 低   | 中   | 已用`$version` 模板 + digest jsonpath；命名规律稳定（v0.3.0/0.3.1/0.3.2 一致） |
| 应用强依赖 WebView2，用户机器缺失             | 低   | 中   | Tauri 安装器内置`MicrosoftEdgeWebview2Setup.exe`；可在 `notes` 提示            |
| 未签名，SmartScreen 拦截                      | 中   | 低   | 上游 README 已说明；可在`notes` 提示                                           |

---

## 七、需要用户决策的点

1. **是否接受 `pre_install` 解压**（方案①），还是倾向官方安装器（方案②）？
   → 用户已表态"安装便携版就行"，**默认按方案①执行**。
2. **是否同时加 arm64**？
   → 建议加（上游稳定提供，成本为零，Scoop 在 arm64 无对应项时会自动回退 64bit）。
3. **`notes` 是否提示 WebView2 与 SmartScreen**？
   → 建议加，属对用户有用的信息。

---

## 八、验收标准

- [ ]  `bucket/agency-agents-app.json` 存在且通过 `verify-manifest.ps1`（FAIL 0）
- [ ]  `scoop install` 后 `agency-agents-app.exe` 可执行、能启动
- [ ]  `scoop uninstall` 后无残留
- [ ]  CI 绿
- [ ]  `README.md` 已同步
- [ ]  决策已记入 `.context/`

---

## 九、参考

- 仓库流程：`.claude/skills/scoop-bucket/SKILL.md`（流程 A）
- 踩坑清单：`.claude/skills/scoop-bucket/references/pitfalls.md`
- 校验脚本：`.claude/skills/scoop-bucket/scripts/verify-manifest.ps1`
- 同类参考清单：`bucket/patheditor-gui.json`（GUI 应用，含 shortcuts）
- Scoop 解压源码：`$(scoop prefix scoop)\lib\decompress.ps1`、`lib\depends.ps1`
