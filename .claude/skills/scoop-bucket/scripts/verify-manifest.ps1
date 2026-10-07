<#
.SYNOPSIS
    校验 Scoop bucket 清单，一次覆盖 CI 会跑到的全部检查。

.DESCRIPTION
    把"每次添加应用都要重新推导一遍"的确定性检查固化下来：
      1. JSON 语法
      2. 必填字段完整性
      3. Scoop 官方 Schema 校验（复用 Scoop 自带的 Scoop.Validator.dll，与 CI 同一份）
      4. 文件级规则（BOM / CRLF / 结尾换行 / 行尾空格 / Tab 缩进）—— 复现 Scoop-00File.Tests.ps1
      5. checkver（调用 bucket 自带 bin\checkver.ps1）
      6. URL 可达性（自行 HEAD 请求所有架构的 URL）
      7. 下载产物实测哈希，与清单声明值比对
      8. 解压列出压缩包内容，确认 bin/shortcuts 指向的文件确实存在
      9. notes 里 $dir 占位符路径的存在性（仅当该应用已安装）

    ⚠ 本文件必须保持「字符串字面量纯 ASCII」。
    CI 的 Code Syntax 测试跑在 Windows PowerShell 5.1 上，它用 Get-Content 按系统
    ANSI 代码页读取本文件。cp1252 下字节 0x91-0x94 会解成 ' ' " " 四个智能引号，
    而 PowerShell 认它们是引号 —— 只要某个非 ASCII 字符的 UTF-8 字节落在该区间，
    字符串就会被提前终止并报一堆 "Unexpected token"。
    注释里的中文是安全的（注释到行尾即止，且高位字节不会解出换行或反引号）。

.PARAMETER ManifestPath
    清单文件路径，如 bucket\foo.json

.PARAMETER BucketRepo
    bucket 仓库根目录，用于定位 bin\ 下的校验工具。
    省略时按脚本自身位置自动推断（脚本位于 <repo>\.claude\skills\...）。

.PARAMETER SkipNetwork
    跳过所有联网检查（步骤 5/6/7）

.PARAMETER SkipDownload
    跳过产物下载与哈希实测（步骤 7/8），保留 checkver/checkurls

.EXAMPLE
    .\verify-manifest.ps1 -ManifestPath '.\bucket\foo.json'

.EXAMPLE
    # 离线快速检查，只跑本地规则
    .\verify-manifest.ps1 -ManifestPath '.\bucket\foo.json' -SkipNetwork
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $ManifestPath,

    [string] $BucketRepo,

    [switch] $SkipNetwork,
    [switch] $SkipDownload
)

$ErrorActionPreference = 'Stop'

# 仓库根自动定位：本脚本位于 <repo>\.claude\skills\<skill>\scripts\，
# 向上四级即仓库根。定位失败（例如脚本被复制到仓库外）时退回硬编码路径。
if (-not $BucketRepo) {
    $guess = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
    $BucketRepo = if (Test-Path -LiteralPath (Join-Path $guess 'bucket')) {
        $guess
    } else {
        'D:\Code\doing_exercises\programs\scoop-bucket'
    }
}

# ---------- 结果收集 ----------
# 注意：哈希键必须是纯 ASCII（原因见文件头）。
$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}{2}" -f $(if ($Ok) { 'OK  ' } else { 'FAIL' }), $Name, $(if ($Detail) { " -- $Detail" } else { '' })) -ForegroundColor $color
}

function Add-Skip {
    param([string]$Name, [string]$Why)
    $script:Results.Add([pscustomobject]@{ Check = $Name; Result = 'SKIP'; Detail = $Why })
    Write-Host ("  [SKIP] {0} -- {1}" -f $Name, $Why) -ForegroundColor DarkGray
}

# 计算文件 SHA256（小写十六进制）。
# 刻意不用 Get-FileHash：它来自 Microsoft.PowerShell.Utility，而本机 PSModulePath 把
# pwsh 7 的 Modules 目录排在 Windows PowerShell 5.1 之前，5.1 会静默加载不兼容的
# 7.0.0.0 版模块并失败（Import-Module 不报错但命令仍不可用）。改用 .NET 直接算，
# 不依赖模块自动加载，5.1 与 7.x 行为一致。
function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLower()
        } finally { $stream.Dispose() }
    } finally { $sha.Dispose() }
}

# ---------- 解析路径 ----------
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Host "Manifest not found: $ManifestPath" -ForegroundColor Red
    exit 2
}
$manifest = (Resolve-Path -LiteralPath $ManifestPath).Path
$appName = [System.IO.Path]::GetFileNameWithoutExtension($manifest)
$repoRoot = if (Test-Path -LiteralPath $BucketRepo) { (Resolve-Path -LiteralPath $BucketRepo).Path } else { $null }

# Scoop 安装根（顶层定义，供步骤 3 与步骤 8 共用）
$scoopHome = if ($env:SCOOP_HOME) { $env:SCOOP_HOME } else { (scoop prefix scoop) }

Write-Host "`n=== Verify manifest: $appName ===" -ForegroundColor Cyan
Write-Host "Path: $manifest`n"

# ---------- 1) JSON 语法 ----------
$json = $null
try {
    $json = Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json
    Add-Result '1. JSON syntax' $true
} catch {
    Add-Result '1. JSON syntax' $false $_.Exception.Message
    Write-Host "`nJSON parse failed; remaining checks skipped." -ForegroundColor Red
    exit 1
}

# ---------- 2) 必填字段 ----------
$missing = @()
foreach ($f in 'version', 'description', 'homepage', 'license') {
    if (-not $json.$f) { $missing += $f }
}
if (-not $json.architecture) { $missing += 'architecture' }
if (-not $json.bin -and -not $json.shortcuts) { $missing += 'bin|shortcuts' }
if ($json.architecture) {
    foreach ($arch in $json.architecture.PSObject.Properties.Name) {
        $a = $json.architecture.$arch
        if (-not $a.url) { $missing += "architecture.$arch.url" }
        if (-not $a.hash) { $missing += "architecture.$arch.hash" }
    }
}
if ($missing.Count -eq 0) { Add-Result '2. Required fields' $true }
else { Add-Result '2. Required fields' $false ("missing: " + ($missing -join ', ')) }

# ---------- 3) Scoop Schema 校验 ----------
try {
    $dll = Join-Path $scoopHome 'supporting\validator\bin\Scoop.Validator.dll'
    $schema = Join-Path $scoopHome 'schema.json'
    if ((Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath $schema)) {
        if (-not ('Scoop.Validator' -as [type])) { Add-Type -Path $dll }
        $validator = New-Object Scoop.Validator($schema.Replace('\', '/'), $true)
        $null = $validator.Validate($manifest)
        if ($validator.Errors.Count -eq 0) {
            Add-Result '3. Scoop schema' $true
        } else {
            Add-Result '3. Scoop schema' $false "$($validator.Errors.Count) error(s)"
            Write-Host $validator.ErrorsAsString -ForegroundColor Yellow
        }
    } else {
        Add-Skip '3. Scoop schema' 'Scoop.Validator.dll or schema.json not found'
    }
} catch {
    Add-Skip '3. Scoop schema' "validator load failed: $($_.Exception.Message)"
}

# ---------- 4) 文件级规则（复现 Scoop-00File.Tests.ps1） ----------
$fileIssues = @()
$bytes = [System.IO.File]::ReadAllBytes($manifest)

# 4a) BOM
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $fileIssues += 'UTF-8 BOM' }

$text = [System.IO.File]::ReadAllText($manifest)

# 4b) 结尾换行
if (-not ($text.Length -gt 0 -and $text[-1] -eq "`n")) { $fileIssues += 'no trailing newline' }

# 4c) CRLF（CI 断言：按 \r\n 切分后不得残留 \r 或 \n）
$lines = [regex]::Split($text, '\r\n')
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ([regex]::match($lines[$i], '\r|\n').success) { $fileIssues += "line $($i+1) not CRLF"; break }
}

# 4d) 空文件守卫（CI 在 CRLF 测试里会 throw）
if ($bytes.Length -eq 0) { $fileIssues += 'file is empty (CI rejects 0-byte files)' }

# 4e/4f) 行尾空格 + Tab 缩进
$rl = [System.IO.File]::ReadAllLines($manifest)
for ($i = 0; $i -lt $rl.Count; $i++) {
    if ($rl[$i] -match '\s+$') { $fileIssues += "line $($i+1) trailing whitespace" }
    if ($rl[$i] -notmatch '^[ ]*(\S|$)') { $fileIssues += "line $($i+1) tab indent" }
}
if ($fileIssues.Count -eq 0) { Add-Result "4. File rules ($($rl.Count) lines)" $true }
else { Add-Result '4. File rules' $false (($fileIssues | Select-Object -First 6) -join '; ') }

# ---------- 5) checkver ----------
$checkverScript = if ($repoRoot) { Join-Path $repoRoot 'bin\checkver.ps1' } else { $null }
if ($SkipNetwork) {
    Add-Skip '5. checkver' 'skipped (-SkipNetwork)'
} elseif ($checkverScript -and (Test-Path -LiteralPath $checkverScript)) {
    # 注意：bin\checkver.ps1 用 Write-Host 输出，走信息流(6)，必须 6>&1 才能捕获
    $out = & $checkverScript -App $manifest 6>&1 | Out-String
    $m = [regex]::Match($out, [regex]::Escape($appName) + ':\s*(\S+)')
    if ($m.Success) {
        $found = $m.Groups[1].Value
        Add-Result '5. checkver' ($found -eq $json.version) "resolved $found, manifest says $($json.version)"
    } elseif ($out -match '(?i)error|exception|could not|not found') {
        Add-Result '5. checkver' $false (($out.Trim() -split "`n") | Select-Object -Last 1)
    } else {
        Add-Result '5. checkver' $false "cannot parse version from output: $($out.Trim())"
    }
} else {
    Add-Skip '5. checkver' 'bin\checkver.ps1 not found'
}

# ---------- 6) URL 可达性 ----------
# 刻意不用 bucket 的 bin\checkurls.ps1：它用多次 Write-Host -NoNewline 输出，
# 捕获时每个片段各成一行（连 [2][2][0] 里的数字都被换行拆开），解析极脆弱。
# 这里自行发 HEAD 请求，确定性强且能精确指出是哪个 URL 失败。
if ($SkipNetwork) {
    Add-Skip '6. URL reachability' 'skipped (-SkipNetwork)'
} else {
    $urls = @()
    foreach ($archName in $json.architecture.PSObject.Properties.Name) {
        $u = $json.architecture.$archName.url
        if ($u) { $urls += (($u -split '#')[0]) }
    }
    $badUrls = @()
    foreach ($u in $urls) {
        try {
            $resp = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 30
            if ($resp.StatusCode -ge 400) { $badUrls += "$u ($($resp.StatusCode))" }
        } catch {
            $badUrls += "$u ($($_.Exception.Message))"
        }
    }
    Add-Result '6. URL reachability' ($badUrls.Count -eq 0) $(if ($badUrls.Count -eq 0) { "$($urls.Count)/$($urls.Count) reachable" } else { $badUrls -join '; ' })
}

# ---------- 7/8) 下载实测哈希 + 解压验证 bin 目标 ----------
if ($SkipDownload -or $SkipNetwork) {
    Add-Skip '7. Hash check' 'skipped (-SkipDownload or -SkipNetwork)'
    Add-Skip '8. Archive contents' 'skipped (-SkipDownload or -SkipNetwork)'
} else {
    # 只校验当前架构（按 PROCESSOR_ARCHITECTURE 选，缺则退回 64bit）
    $archKey = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -and $json.architecture.arm64) { 'arm64' } else { '64bit' }
    $arch = $json.architecture.$archKey
    $tmp = Join-Path $env:TEMP ("verify-$appName-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        # 从 URL 推断文件名（处理 #/ 重命名语法：取 # 前部分）
        $url = ($arch.url -split '#')[0]
        $fileName = Split-Path $url -Leaf
        $dest = Join-Path $tmp $fileName
        Write-Host "  downloading: $url" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -MaximumRedirection 5

        $actual = (Get-Sha256 $dest)
        $declared = ($arch.hash -replace '^sha256:', '').ToLower()
        Add-Result '7. Hash check' ($actual -eq $declared) $(if ($actual -eq $declared) { $actual.Substring(0,16) + '...' } else { "declared=$($declared.Substring(0,16))... actual=$($actual.Substring(0,16))..." })

        # 解压列出内容。
        # 用 7-Zip 而非 Expand-Archive：后者只认 zip，而 bucket 里存在 NSIS 安装器
        # （.exe）、.7z、.tar.gz 等形态。7z 覆盖全部，且与 Scoop 自身的解压器一致。
        # 排除 $PLUGINSDIR / $TEMP 与 Scoop 的 pre_install 保持一致，避免把
        # NSIS 载荷目录当成"包内文件"而误判 bin 目标。
        $ext = Join-Path $tmp 'x'
        New-Item -ItemType Directory -Path $ext -Force | Out-Null
        # 自行定位 7z：不调用 Scoop 的 Get-HelperPath（本脚本不加载 Scoop 的 lib）。
        # 顺序：Scoop 内置 helper -> PATH 上的 7z。
        $sevenZip = $null
        $helper = Join-Path $scoopHome 'apps\7zip\current\7z.exe'
        if (Test-Path -LiteralPath $helper) {
            $sevenZip = $helper
        } else {
            $cmd = Get-Command 7z -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($cmd) { $sevenZip = $cmd.Source }
        }
        if (-not $sevenZip) {
            Add-Skip '8. Archive contents' '7-Zip not found'
        } else {
            $null = & $sevenZip x $dest "-o$ext" '-xr!$PLUGINSDIR' '-xr!$TEMP' '-y' 2>&1
            if ($LASTEXITCODE -ne 0) {
                Add-Result '8. Archive contents' $false "7-Zip could not extract (exit $LASTEXITCODE)"
            } else {
                $entries = Get-ChildItem -LiteralPath $ext -Recurse -File |
                    ForEach-Object { $_.FullName.Substring($ext.Length + 1).Replace('\', '/') }
                Write-Host "  archive contents:" -ForegroundColor DarkGray
                $entries | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

                # 校验 bin / shortcuts 指向的文件确实存在
                $targets = @()
                if ($json.bin) { $targets += @($json.bin | ForEach-Object { if ($_ -is [string]) { $_ } else { $_[0] } }) }
                if ($json.shortcuts) { $targets += @($json.shortcuts | ForEach-Object { $_[0] }) }
                $missingBin = @($targets | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $ext $_)) })
                if ($missingBin.Count -eq 0) {
                    Add-Result '8. Archive contents' $true "bin/shortcuts targets present: $($targets -join ', ')"
                } else {
                    Add-Result '8. Archive contents' $false "not found in archive: $($missingBin -join ', ')"
                }
            }
        }
    } catch {
        Add-Result '7. Hash check' $false $_.Exception.Message
        Add-Skip '8. Archive contents' 'download failed'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------- 9) notes 里 $dir 路径的存在性（仅已安装时） ----------
if ($json.notes) {
    $noteText = @($json.notes) -join "`n"
    $appDir = Join-Path (Split-Path -Parent (Split-Path -Parent (scoop prefix scoop))) "$appName\current"
    $quoted = [regex]::Matches($noteText, '"([^"]*\$dir[^"]*)"') | ForEach-Object { $_.Groups[1].Value }
    if ($quoted.Count -eq 0) {
        Add-Skip '9. notes paths' 'no $dir placeholder in notes'
    } elseif (-not (Test-Path -LiteralPath $appDir)) {
        Add-Skip '9. notes paths' "app not installed (no $appDir)"
    } else {
        $bad = @()
        foreach ($q in $quoted) {
            $resolved = $q.Replace('$dir', $appDir)
            try { $full = [System.IO.Path]::GetFullPath($resolved) } catch { $bad += "$q (invalid path)"; continue }
            if (-not (Test-Path -LiteralPath $full)) { $bad += "$q -> $full not found" }
        }
        Add-Result '9. notes paths' ($bad.Count -eq 0) $(if ($bad.Count -eq 0) { "$($quoted.Count) path(s) exist" } else { $bad -join '; ' })
    }
}

# ---------- 汇总 ----------
$failed = @($script:Results | Where-Object { $_.Result -eq 'FAIL' })
Write-Host ""
Write-Host "=== Summary: PASS $(@($script:Results | Where-Object { $_.Result -eq 'PASS' }).Count) / FAIL $($failed.Count) / SKIP $(@($script:Results | Where-Object { $_.Result -eq 'SKIP' }).Count) ===" -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })

if ($failed.Count -gt 0) {
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.Check, $_.Detail) -ForegroundColor Red }
    Write-Host "`nFix the above before committing." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nAll checks passed. Safe to commit." -ForegroundColor Green
exit 0
