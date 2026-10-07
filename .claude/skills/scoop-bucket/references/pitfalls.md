# 踩坑清单与字段速查

来源：2026-10-03 为 `aoci-code` 建清单时实测所得。每条都带判据或复现方式。

---

## 一、checkver 与 autoupdate

### 1.1 `/releases/latest` 会跳过 prerelease

GitHub 的 `/releases/latest` 端点**不返回被标记为 prerelease 的发布**。若上游所有 release 都是 prerelease，该端点直接 **404**，`checkver` 会永久失败。

```powershell
gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'   # 404 ⇒ 命中此坑
```

改用列表端点取最新一条：

```json
"checkver": {
    "url": "https://api.github.com/repos/<owner>/<repo>/releases",
    "jsonpath": "$[0].tag_name",
    "regex": "v?([\\d.]+(?:-[0-9A-Za-z.-]+)?)"
}
```

**这个原因必须写进清单的 `##` 字段**，否则以后有人"顺手优化"回 `/releases/latest` 会把自动更新搞挂：

```json
"##": "All upstream releases are flagged as pre-releases, so the /releases/latest endpoint returns 404. Use the list endpoint and take the newest entry instead."
```

### 1.2 Scoop 的 jsonpath 是完整 JSONPath

底层是 **Newtonsoft.Json 的 `SelectTokens`**（`lib/json.ps1:108`），不是简化实现。所以数组索引、filter 表达式都可用：

```json
"jsonpath": "$[0].tag_name"
"jsonpath": "$.assets[?(@.name == 'foo_$version_x64.zip')].digest"
```

### 1.3 autoupdate 哈希优先用 asset `digest`

GitHub 现在给每个 asset 返回 `digest` 字段（形如 `sha256:abc...`），比让 Scoop 去抓 `SHA256SUMS` 再写正则更稳：

```json
"hash": {
    "url": "https://api.github.com/repos/<owner>/<repo>/releases/tags/v$version",
    "jsonpath": "$.assets[?(@.name == '<asset>_$version_<platform>.zip')].digest"
}
```

### 1.4 `autoupdate` 写回时会剥掉 `sha256:` 前缀

Scoop 从 digest 拿到 `sha256:abc...`，但**写回清单时只写裸十六进制**。所以静态 `hash` 字段也用裸 hex（不带前缀），这样下次 `-ForceUpdate` 不产生无意义 diff。

**验证手段**：对清单跑一次 `checkver -App <path> -ForceUpdate`，然后比对文件哈希是否变化 —— 无变化说明清单是 autoupdate 稳定的。

```powershell
$before = (Get-FileHash $m -Algorithm SHA256).Hash
& .\bin\checkver.ps1 -App $m -ForceUpdate
$after = (Get-FileHash $m -Algorithm SHA256).Hash
"changed: $($before -ne $after)"     # False = 稳定
```

### 1.5 版本号 regex 要能吞下 prerelease 后缀

```json
"regex": "v?([\\d.]+(?:-[0-9A-Za-z.-]+)?)"
```

`v0.1.0-rc17` → 捕获 `0.1.0-rc17`；`v0.1.0` → 捕获 `0.1.0`。

---

## 二、清单字段速查


| 字段                      | 要点                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------ |
| `version`                 | 与 tag 一致但**去掉 `v` 前缀**（tag `v0.1.0-rc17` → `0.1.0-rc17`）；asset 名里通常是去掉 `v` 的形式 |
| `description`             | 一句话，不要重复应用名，不要以句号结尾                                                               |
| `license`                 | 用 SPDX 标识符。GitHub API 返回`NOASSERTION` 时读 `LICENSE` 正文首行                                 |
| `architecture`            | 同时有 amd64/arm64 时两个都写；Scoop 在 arm64 无对应项时会自动回退`64bit`                            |
| `bin`                     | 值必须是**压缩包内**的真实相对路径。写完务必用脚本第 8 项验证                                        |
| `shortcuts`               | 数组套数组：`[["app.exe", "显示名"]]`；指向的 exe 同样要在包内存在                                   |
| `notes`                   | 只支持`$dir`、`$original_dir`、`$persist_dir` 三个替换变量（`install.ps1:359`），**没有 `$shimdir`** |
| `##`                      | 注释字段，用来记录非常规决策（如 1.1 的 prerelease 原因）                                            |
| `checkver` / `autoupdate` | 见第一节                                                                                             |

### 2.1 `notes` 里的路径：`current` 是一层目录

Scoop 的 `apps\<app>\current` 是 **junction**，它本身是一层路径。从它出发到 `shims\` 需要**三个** `..`：

```
$dir\..\..\..\shims\<app>.exe     ⇒  ...\Scoop\shims\<app>.exe     ✅
$dir\..\..\shims\<app>.exe        ⇒  ...\Scoop\apps\shims\<app>.exe  ❌
```

**踩过的坑**：少写一层，路径指向不存在的目录。

### 2.2 `scoop info` 渲染 notes 时把 `$dir` 显示成 `<root>`

- `scoop info` 用占位符 `<root>`（`scoop-info.ps1:253`）
- `scoop install` 展开成真实路径（`install.ps1:359`）

**后果**：光看 `scoop info` 的输出**无法发现路径写错**，必须实际 `Test-Path` 或看安装输出。校验脚本第 9 项就是干这个的。

### 2.3 宿主配置里的路径要跨版本稳定

`apps\<app>\current\<exe>` 与 `shims\<app>.exe` **都**是版本稳定的：

- `current` 是 junction，升级时被重新指向新版本目录，路径字符串不变
- `shims\<app>.exe` 是 Scoop 的契约路径，只要 manifest 有 `bin` 就存在

区别只在于 shim 多一个包装进程（实测 stdio 转发正常、硬杀无孤儿进程）。**推荐 shim**：它是 Scoop 公开承诺的接口，而 `apps\...\current\...` 属于内部布局。

---

## 三、文件级规则（CI）

CI 的 `Scoop-00File.Tests.ps1` 对**仓库内所有非二进制文件**断言，只需一条不过就红：


| 规则         | 判据                                           |
| -------------- | ------------------------------------------------ |
| 无 UTF-8 BOM | 前三字节不得是`EF BB BF`                       |
| 以换行结尾   | 最后一个字符必须是`\n`                         |
| 行尾为 CRLF  | 按`\r\n` 切分后，任一段内不得残留 `\r` 或 `\n` |
| 无行尾空格   | 每行不匹配`\s+$`                               |
| 无 Tab 缩进  | 每行匹配 `^[ ]*(\S                             |
| **非空文件** | 0 字节会 throw —— 藏在 CRLF 测试里，见 3.3   |

### 3.1 `.gitattributes` 决定"检出后"的行尾，不决定工作区现状

仓库声明 `* text=auto eol=crlf`：

- 索引里存 **LF**，检出到工作区转 **CRLF**
- 所以工作区文件是 LF 还是 CRLF **不影响 CI**（CI 是新检出）
- 但 `.editorconfig` 要求 `end_of_line = crlf`，工作区应保持 CRLF

**踩过的坑**：`Write` 工具写文件产出 **LF**，与仓库约定不符。改完文本文件要归一化：

```powershell
$t = [System.IO.File]::ReadAllText($f)
[System.IO.File]::WriteAllText($f, ($t -replace "`r`n","`n" -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
```

`Edit` 工具没有这个问题（字符串替换，保留原行尾）。

### 3.2 猜不出 CI 会怎么判？直接复现

用 Scoop 自带的同一个校验器，不必装 Pester：

```powershell
$sh = (scoop prefix scoop)
if (-not ('Scoop.Validator' -as [type])) { Add-Type -Path "$sh\supporting\validator\bin\Scoop.Validator.dll" }
$v = New-Object Scoop.Validator("$sh/schema.json", $true)
$v.Validate($manifestPath)
$v.ErrorsAsString      # 空 = 通过
```

> CI 里的 `bin/test.ps1` 需要 Pester 5.2.0 + BuildHelpers，本机通常是 Pester 3.4.0。**不要为此擅自安装模块改用户环境** —— 用上面的方式复现等价检查即可。

### 3.3 CI 拒绝 0 字节文件（藏在 CRLF 测试里）

`Scoop-00File.Tests.ps1` 的 `It 'file newlines are CRLF'` 开头有一个守卫：

```powershell
$content = [System.IO.File]::ReadAllText($file)
if (!$content) { throw "File contents are null: $($file)" }
```

**任何 0 字节文件都会让这个测试抛异常，而失败项显示的名字是 `file newlines are CRLF`** ——
极具误导性，会把人往行尾方向引。

> 本仓库既有的 `.gitkeep`（`scripts/`、`deprecated/`）都**带说明文字**而非空文件 ——
> 那正是上游模板为绕开这条规则的做法。新建 `.gitkeep` 时照做。

**踩过的坑**：CCG 的 `.context` 模板会生成 0 字节的 `history/commits.jsonl` 与
`history/archives/.gitkeep`，两者都让 CI 变红。修法是给它们内容；注意 `commits.jsonl`
**必须写 `\r\n` 而不能只写 `\n`** —— 只写 `\n` 会反过来被 CRLF 测试判为非 CRLF。

### 3.4 `.ps1` 的字符串字面量必须是纯 ASCII（5.1 + ANSI 代码页）

CI 的 Code Syntax 测试跑在 **Windows PowerShell 5.1** 上，用的是：

```powershell
$contents = Get-Content -Path $scriptPath     # 没有 -Encoding
```

5.1 的 `Get-Content` 在无 BOM 时按**系统 ANSI 代码页**解码。本仓库的 `.ps1` 是无 BOM 的
UTF-8，于是在 GitHub runner（cp1252）上会发生：

- cp1252 把字节 `0x91`–`0x94` 解成 `'` `'` `"` `"` 四个**智能引号**，而 **PowerShell 认它们是引号**
- 任何非 ASCII 字符只要某个 UTF-8 字节落在这个区间，就会**在字符串中间注入一个引号**
- 于是字符串提前终止，报出一堆 `Unexpected token` / `Missing closing '}'`

常用汉字里约 6% 命中该区间（例如破折号 `—` = `E2 80 94`），所以这**不是偶发而是概率性必炸**。

**规则**：

- `.ps1` 的**字符串字面量**（含哈希键名、输出文案）一律纯 ASCII
- **注释里的中文是安全的** —— 注释到行尾即止，且 `0x80` 以上的字节不会解出换行或反引号
- 别指望加 UTF-8 BOM 绕过：CI 的 `files do not contain leading UTF-8 BOM` 会直接判红

**复现方式**（本机代码页是 65001 时测不出来，必须显式按目标代码页解码）：

```powershell
$bytes = [System.IO.File]::ReadAllBytes($scriptPath)
foreach ($cp in 1252, 936, 437) {
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize(
        [System.Text.Encoding]::GetEncoding($cp).GetString($bytes), [ref]$errors)
    "cp$cp errors=$($errors.Count)"
}
```

三种代码页都必须为 0。

### 3.5 Scoop **不会**自动解压 `.exe` 类型的 URL

`lib/decompress.ps1` 的 `Invoke-Extraction` 按**文件扩展名**分派解压方式：

```powershell
switch -regex ($Name[$i]) {
    '\.zip$' { $extractFn = 'Expand-7zipArchive' }   # 或 Expand-ZipArchive
    '\.msi$' { $extractFn = 'Expand-MsiArchive' }
    '\.exe$' { if ($Manifest.innosetup) { $extractFn = 'Expand-InnoArchive' } ; continue }
    { Test-7zipRequirement -Uri $_ } { $extractFn = 'Expand-7zipArchive' }
}
```

两个要点：

1. `.exe` 分支**只在 `innosetup` 为真时**才解压，且只走 InnoSetup 解压器
2. 兜底的 `Test-7zipRequirement`（`lib/depends.ps1`）正则**不匹配 `.exe`**：

   ```
   \.(001|7z|bz(ip)?2?|gz|img|iso|lzma|lzh|nupkg|rar|tar|t[abgpx]z2?|t?zst|xz)(\.[^\d.]+)?$
   ```

**后果**：`"url"` 指向 `.exe` 时，Scoop 会把文件**原样放进安装目录**，然后找不到 `bin` 指向的目标。
"7z 能解开这个文件" ≠ "Scoop 会去解开它" —— 前者是格式能力，后者是按扩展名的分派。

**对策**：用 `pre_install` 显式解压。`Expand-7zipArchive` 在 `pre_install` 中**可直接调用**
（`libexec/scoop-install.ps1` 会 dot-source `lib/decompress.ps1`），`$dir` / `$version` /
`$original_dir` / `$persist_dir` 也都可见（`Invoke-HookScript` 用 `Invoke-Command` 跑脚本块，
动态作用域能看到调用方的局部变量）。

```json
"pre_install": "Expand-7zipArchive -Path \"$dir\\App_${version}_x64-setup.exe\" -DestinationPath $dir -Switches '-xr!$PLUGINSDIR -xr!$TEMP' -Removal"
```

⚠️ **`-Switches` 是单个字符串，不是数组**。写成 `-Switches '-xr!A' '-xr!B'` 会报
`A positional parameter cannot be found that accepts argument '-xr!B'`；必须写成
`-Switches '-xr!A -xr!B'`（函数内部会 `-split`）。

⚠️ **排除开关要自己加**。源码里 `Expand-7zipArchive` 只有 `-xr!*.nsis` 一条内置排除，
网上流传的"自动排除 `$PLUGINSDIR`/`$TEMP`"**在本机这份 Scoop 上不成立**。
不加的话 NSIS 载荷目录（`$PLUGINSDIR\System.dll`、`$TEMP\MicrosoftEdgeWebview2Setup.exe` 等）
会污染安装目录。

**判据**：安装后 `ls apps\<app>\current\`，不应出现 `$PLUGINSDIR` / `$TEMP`。

---

## 四、工具使用陷阱

### 4.0 `Get-FileHash` 在本机 Windows PowerShell 5.1 下不可用

本机 `PSModulePath` 把 **pwsh 7 的 Modules 目录排在 5.1 之前**：

```
...;d:\settings\settings\scoop\apps\powershell\current\Modules;D:\settings\settings\Scoop\modules;...
```

于是 5.1 会去加载 pwsh 7 的 `Microsoft.PowerShell.Utility 7.0.0.0`，**静默失败**：

```powershell
powershell -NoProfile -Command "[bool](Get-Command Get-FileHash -EA SilentlyContinue)"
# False —— 且 Import-Module Microsoft.PowerShell.Utility 也不报错但无效
```

显式指定 5.1 路径才成功（`C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\...`）。

**对策**：跨版本脚本里**优先用 .NET API 而不是 cmdlet**，可完全绕开模块加载问题：

```powershell
function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower() }
        finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}
```

> 同类问题：`Expand-Archive` 只认 zip，遇到 `.7z` / `.tar.gz` / NSIS 会抛异常。
> 校验脚本里改用 7-Zip（`apps\7zip\current\7z.exe`），与 Scoop 自身解压器一致。

### 4.1 `formatjson` 会重写整个目录

`bin/formatjson.ps1` 硬编码 `-Dir ../bucket`，是**就地重写**式规范化。直接跑会连带改掉其他清单。

**做法**：复制到临时目录再跑，比对差异。

```powershell
$tmp = Join-Path $env:TEMP 'fj'; New-Item -ItemType Directory $tmp -Force | Out-Null
Copy-Item .\bucket\<app>.json $tmp
$env:SCOOP_HOME = (scoop prefix scoop)
& "$env:SCOOP_HOME\bin\formatjson.ps1" -Dir $tmp
Compare-Object (Get-Content .\bucket\<app>.json) (Get-Content "$tmp\<app>.json")
Remove-Item $tmp -Recurse -Force
```

> `Compare-Object (Get-Content ...)` 会**归一化行尾**，测不出 CRLF/LF 差异。要测行尾必须用 `[System.IO.File]::ReadAllText/ReadAllBytes`。

### 4.2 Scoop 的 `bin/*.ps1` 用 `Write-Host`，`2>&1` 抓不到

`Write-Host` 走**信息流（stream 6）**，`2>&1` 只合并错误流。要捕获必须 `6>&1`：

```powershell
$out = & .\bin\checkver.ps1 -App $m 6>&1 | Out-String
```

**更糟的是**：`checkurls.ps1` 用多次 `Write-Host -NoNewline` 逐段输出，捕获后**每个片段各成一行**，连 `[2][2][0]` 里的数字都被换行拆开：

```
[<EOL>2<EOL>]<EOL>[<EOL>2<EOL>]<EOL>[<EOL>0<EOL>]
```

**结论**：不要解析这类输出。校验脚本里 URL 检查改为自行发 HEAD 请求（见 `scripts/verify-manifest.ps1` 第 6 项）。

### 4.3 Scoop 仓库模板自带工具链

这个 bucket 由 `ScoopInstaller/BucketTemplate` 生成，`bin/` 下有 `checkver.ps1`、`checkurls.ps1`、`checkhashes.ps1`、`formatjson.ps1`、`test.ps1`。

`checkver.ps1` 支持**直接传清单文件路径**（`Test-Path $App -PathType Leaf` 分支），所以不必先把清单放进 Scoop 的桶副本里：

```powershell
& .\bin\checkver.ps1 -App (Resolve-Path '.\bucket\<app>.json').Path
```

### 4.4 `lhy` 桶注册的是 git 远端

Scoop 有自己的一份 clone（`<SCOOP>\buckets\lhy`）。**工作区里未推送的清单，`scoop checkver <app>` 看不到** —— 查清单要用文件路径形式（4.3）。

---

## 五、验证方法学

### 5.1 哈希三方交叉校验

```powershell
(Get-FileHash $localZip -Algorithm SHA256).Hash          # 本地实测
gh release download <tag> --repo <o>/<r> --pattern SHA256SUMS --output -   # 上游声明
gh api repos/<o>/<r>/releases/tags/<tag> --jq '.assets[] | select(.name=="<asset>") | .digest'  # API digest
```

三者一致才落笔。单靠其中一个都可能被上游的打包错漏骗过。

### 5.2 配置类文件要"照它执行一次"来验证，不要只读内容

读文件发现不了引号转义、参数顺序、路径拼接错误。**解析配置 → 原样 spawn → 看握手**才算验证：

```powershell
$cfg = Get-Content .mcp.json -Raw | ConvertFrom-Json
$srv = $cfg.mcpServers.<name>
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $srv.command; $psi.Arguments = $srv.args -join ' '
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)
$outTask = $p.StandardOutput.ReadToEndAsync()
$p.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"1.0"}}}')
$p.StandardInput.Flush(); Start-Sleep -Seconds 4; $p.StandardInput.Close()
$outTask.Result      # 应含 serverInfo
```

### 5.3 校验脚本必须做反向测试

只会 PASS 的检查等于没有。写完脚本后**故意注入错误**（改坏 URL、删字段、转成 LF）确认它真能 FAIL：

```powershell
$txt = [IO.File]::ReadAllText($orig).Replace("`r`n","`n")           # 注入 LF
$txt = $txt.Replace('"license": "X",', '')                          # 删字段
[IO.File]::WriteAllText($tmp, $txt, (New-Object System.Text.UTF8Encoding($false)))
& $script -ManifestPath $tmp -SkipNetwork       # 期望退出码 1
```

### 5.4 不要从单一样本外推"必然/永远不会"

**踩过的坑**：在临时空仓库里测试，`aoci init` 会创建 `.gitattributes` 并设为 `eol=lf`，据此推断"它必然打红 scoop-bucket 的 CI"。实际对已有 `.gitattributes` 的仓库它**原样保留**，警告不成立。

空仓库样本能回答"会发生什么"，**回答不了"什么时候不发生"**。涉及关键决策时要在实际目标上验证。
