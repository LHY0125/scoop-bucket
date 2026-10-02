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
    .\verify-manifest.ps1 -ManifestPath ..\..\doing_exercises\programs\scoop-bucket\bucket\foo.json

.EXAMPLE
    # 离线快速检查，只跑本地规则
    .\verify-manifest.ps1 -ManifestPath bucket\foo.json -SkipNetwork
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
$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ 检查项 = $Name; 结果 = $(if ($Ok) { 'PASS' } else { 'FAIL' }); 说明 = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}{2}" -f $(if ($Ok) { 'OK  ' } else { 'FAIL' }), $Name, $(if ($Detail) { " — $Detail" } else { '' })) -ForegroundColor $color
}

function Add-Skip {
    param([string]$Name, [string]$Why)
    $script:Results.Add([pscustomobject]@{ 检查项 = $Name; 结果 = 'SKIP'; 说明 = $Why })
    Write-Host ("  [SKIP] {0} — {1}" -f $Name, $Why) -ForegroundColor DarkGray
}

# ---------- 解析路径 ----------
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Host "找不到清单文件: $ManifestPath" -ForegroundColor Red
    exit 2
}
$manifest = (Resolve-Path -LiteralPath $ManifestPath).Path
$appName = [System.IO.Path]::GetFileNameWithoutExtension($manifest)
$repoRoot = if (Test-Path -LiteralPath $BucketRepo) { (Resolve-Path -LiteralPath $BucketRepo).Path } else { $null }

Write-Host "`n=== 校验清单: $appName ===" -ForegroundColor Cyan
Write-Host "路径: $manifest`n"

# ---------- 1) JSON 语法 ----------
$json = $null
try {
    $json = Get-Content -LiteralPath $manifest -Raw -Encoding utf8 | ConvertFrom-Json
    Add-Result '1. JSON 语法' $true
} catch {
    Add-Result '1. JSON 语法' $false $_.Exception.Message
    Write-Host "`nJSON 语法错误，后续检查无法进行。" -ForegroundColor Red
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
if ($missing.Count -eq 0) { Add-Result '2. 必填字段' $true }
else { Add-Result '2. 必填字段' $false ("缺失: " + ($missing -join ', ')) }

# ---------- 3) Scoop Schema 校验 ----------
try {
    $scoopHome = if ($env:SCOOP_HOME) { $env:SCOOP_HOME } else { (scoop prefix scoop) }
    $dll = Join-Path $scoopHome 'supporting\validator\bin\Scoop.Validator.dll'
    $schema = Join-Path $scoopHome 'schema.json'
    if ((Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath $schema)) {
        if (-not ('Scoop.Validator' -as [type])) { Add-Type -Path $dll }
        $validator = New-Object Scoop.Validator($schema.Replace('\', '/'), $true)
        $null = $validator.Validate($manifest)
        if ($validator.Errors.Count -eq 0) {
            Add-Result '3. Scoop Schema' $true
        } else {
            Add-Result '3. Scoop Schema' $false "$($validator.Errors.Count) 个错误"
            Write-Host $validator.ErrorsAsString -ForegroundColor Yellow
        }
    } else {
        Add-Skip '3. Scoop Schema' '未找到 Scoop.Validator.dll 或 schema.json'
    }
} catch {
    Add-Skip '3. Scoop Schema' "加载校验器失败: $($_.Exception.Message)"
}

# ---------- 4) 文件级规则（复现 Scoop-00File.Tests.ps1） ----------
$fileIssues = @()
$bytes = [System.IO.File]::ReadAllBytes($manifest)

# 4a) BOM
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $fileIssues += 'UTF-8 BOM' }

$text = [System.IO.File]::ReadAllText($manifest)

# 4b) 结尾换行
if (-not ($text.Length -gt 0 -and $text[-1] -eq "`n")) { $fileIssues += '结尾缺换行' }

# 4c) CRLF（CI 断言：按 \r\n 切分后不得残留 \r 或 \n）
$lines = [regex]::Split($text, '\r\n')
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ([regex]::match($lines[$i], '\r|\n').success) { $fileIssues += "第 $($i+1) 行非 CRLF"; break }
}

# 4d/4e) 行尾空格 + Tab 缩进
$rl = [System.IO.File]::ReadAllLines($manifest)
for ($i = 0; $i -lt $rl.Count; $i++) {
    if ($rl[$i] -match '\s+$') { $fileIssues += "第 $($i+1) 行行尾空格" }
    if ($rl[$i] -notmatch '^[ ]*(\S|$)') { $fileIssues += "第 $($i+1) 行 Tab 缩进" }
}
if ($fileIssues.Count -eq 0) { Add-Result "4. 文件级规则 ($($rl.Count) 行)" $true }
else { Add-Result '4. 文件级规则' $false (($fileIssues | Select-Object -First 6) -join '; ') }

# ---------- 5) checkver ----------
$checkverScript = if ($repoRoot) { Join-Path $repoRoot 'bin\checkver.ps1' } else { $null }
if ($SkipNetwork) {
    Add-Skip '5. checkver' '已指定 -SkipNetwork'
} elseif ($checkverScript -and (Test-Path -LiteralPath $checkverScript)) {
    # 注意：bin\checkver.ps1 用 Write-Host 输出，走信息流(6)，必须 6>&1 才能捕获
    $out = & $checkverScript -App $manifest 6>&1 | Out-String
    $m = [regex]::Match($out, [regex]::Escape($appName) + ':\s*(\S+)')
    if ($m.Success) {
        $found = $m.Groups[1].Value
        Add-Result '5. checkver' ($found -eq $json.version) "解析出 $found，清单声明 $($json.version)"
    } elseif ($out -match '(?i)error|exception|could not|not found') {
        Add-Result '5. checkver' $false (($out.Trim() -split "`n") | Select-Object -Last 1)
    } else {
        Add-Result '5. checkver' $false "无法从输出解析版本: $($out.Trim())"
    }
} else {
    Add-Skip '5. checkver' '未找到 bin\checkver.ps1'
}

# ---------- 6) URL 可达性 ----------
# 刻意不用 bucket 的 bin\checkurls.ps1：它用多次 Write-Host -NoNewline 输出，
# 捕获时每个片段各成一行（连 [2][2][0] 里的数字都被换行拆开），解析极脆弱。
# 这里自行发 HEAD 请求，确定性强且能精确指出是哪个 URL 失败。
if ($SkipNetwork) {
    Add-Skip '6. URL 可达性' '已指定 -SkipNetwork'
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
    Add-Result '6. URL 可达性' ($badUrls.Count -eq 0) $(if ($badUrls.Count -eq 0) { "$($urls.Count)/$($urls.Count) 可达" } else { $badUrls -join '; ' })
}

# ---------- 7/8) 下载实测哈希 + 解压验证 bin 目标 ----------
if ($SkipDownload -or $SkipNetwork) {
    Add-Skip '7. 哈希实测' '已指定 -SkipDownload 或 -SkipNetwork'
    Add-Skip '8. 压缩包内容' '已指定 -SkipDownload 或 -SkipNetwork'
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
        Write-Host "  下载中: $url" -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -MaximumRedirection 5

        $actual = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
        $declared = ($arch.hash -replace '^sha256:', '').ToLower()
        Add-Result '7. 哈希实测' ($actual -eq $declared) $(if ($actual -eq $declared) { $actual.Substring(0,16) + '...' } else { "声明=$($declared.Substring(0,16))... 实测=$($actual.Substring(0,16))..." })

        # 解压列出内容
        $ext = Join-Path $tmp 'x'
        Expand-Archive -LiteralPath $dest -DestinationPath $ext -Force
        $entries = Get-ChildItem -LiteralPath $ext -Recurse -File | ForEach-Object { $_.FullName.Substring($ext.Length + 1).Replace('\', '/') }
        Write-Host "  压缩包内容:" -ForegroundColor DarkGray
        $entries | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

        # 校验 bin / shortcuts 指向的文件确实存在
        $targets = @()
        if ($json.bin) { $targets += @($json.bin | ForEach-Object { if ($_ -is [string]) { $_ } else { $_[0] } }) }
        if ($json.shortcuts) { $targets += @($json.shortcuts | ForEach-Object { $_[0] }) }
        $missingBin = @($targets | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $ext $_)) })
        if ($missingBin.Count -eq 0) {
            Add-Result '8. 压缩包内容' $true "bin/shortcuts 目标均存在: $($targets -join ', ')"
        } else {
            Add-Result '8. 压缩包内容' $false "这些目标在包内不存在: $($missingBin -join ', ')"
        }
    } catch {
        Add-Result '7. 哈希实测' $false $_.Exception.Message
        Add-Skip '8. 压缩包内容' '下载失败'
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
        Add-Skip '9. notes 路径' 'notes 中无 $dir 占位符'
    } elseif (-not (Test-Path -LiteralPath $appDir)) {
        Add-Skip '9. notes 路径' "应用未安装，无法解析 \$dir（$appDir 不存在）"
    } else {
        $bad = @()
        foreach ($q in $quoted) {
            $resolved = $q.Replace('$dir', $appDir)
            try { $full = [System.IO.Path]::GetFullPath($resolved) } catch { $bad += "$q (路径非法)"; continue }
            if (-not (Test-Path -LiteralPath $full)) { $bad += "$q → $full 不存在" }
        }
        Add-Result '9. notes 路径' ($bad.Count -eq 0) $(if ($bad.Count -eq 0) { "$($quoted.Count) 个路径均存在" } else { $bad -join '; ' })
    }
}

# ---------- 汇总 ----------
$failed = @($script:Results | Where-Object { $_.结果 -eq 'FAIL' })
Write-Host ""
Write-Host "=== 汇总: PASS $(@($script:Results | Where-Object { $_.结果 -eq 'PASS' }).Count) / FAIL $($failed.Count) / SKIP $(@($script:Results | Where-Object { $_.结果 -eq 'SKIP' }).Count) ===" -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })

if ($failed.Count -gt 0) {
    Write-Host "`n未通过项:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host ("  - {0}: {1}" -f $_.检查项, $_.说明) -ForegroundColor Red }
    Write-Host "`n提交前请先修复上述问题。" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n全部通过。可提交。" -ForegroundColor Green
exit 0
