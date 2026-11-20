<#
.SYNOPSIS
    Check and update bucket/unc.json from the UGOS Pro release API.

.DESCRIPTION
    The UGOS release API returns 404 to requests from GitHub-hosted runners,
    so Excavator cannot follow this package. Run this script locally instead.

    Steps:
      1. Query the latest release from api.ugnas.com
      2. Compare it with the version in bucket/unc.json
      3. Download the Windows amd64 zip and verify SHA256 against checksums.txt
      4. Confirm unc-v<version>-windows-amd64/unc.exe exists in the archive
      5. Rewrite version, url, hash and extract_dir in the manifest
      6. Run verify-manifest.ps1 (unless -SkipVerify)

    This file is intentionally ASCII-only: CI tokenizes .ps1 files with
    Windows PowerShell 5.1 under the system ANSI code page, and non-ASCII
    string literals can be decoded into quotes.

.PARAMETER ManifestPath
    Manifest to update. Defaults to <repo>/bucket/unc.json.

.PARAMETER Force
    Re-download and rewrite even when the manifest already has the latest version.

.PARAMETER DryRun
    Report what would change without touching the manifest.

.PARAMETER SkipVerify
    Skip verify-manifest.ps1 after writing.

.EXAMPLE
    .\update-unc.ps1 -DryRun

.EXAMPLE
    .\update-unc.ps1
#>
[CmdletBinding()]
param(
    [string]$ManifestPath,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

# Repo root: this script lives in <repo>\.claude\skills\scoop-bucket\scripts\
$scriptDir = Split-Path -Parent $PSCommandPath
$skillDir = Split-Path -Parent $scriptDir
$skillsDir = Split-Path -Parent $skillDir
$claudeDir = Split-Path -Parent $skillsDir
$repoRoot = Split-Path -Parent $claudeDir

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $repoRoot 'bucket\unc.json'
}
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Manifest not found: $ManifestPath"
}
$manifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

$apiUrl = 'https://api.ugnas.com/api/system/v1/sa/unc/releases/latest'
$downloadBase = 'https://file1-cn.ugnas.com/nas-cli'

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
        } finally {
            $stream.Dispose()
        }
    } finally {
        $sha.Dispose()
    }
}

function Get-JsonWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$Attempts = 3
    )
    $last = $null
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 30
            return ($resp.Content | ConvertFrom-Json)
        } catch {
            $last = $_
            if ($i -lt $Attempts) {
                Write-Host "    request failed (attempt $i/$Attempts): $($_.Exception.Message)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 2
            }
        }
    }
    throw $last
}

function Invoke-DownloadWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )
    $last = $null
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
            return
        } catch {
            $last = $_
            if ($i -lt 3) {
                Write-Host "    download failed (attempt $i/3): $($_.Exception.Message)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 2
            }
        }
    }
    throw $last
}

function Get-ExpectedHash {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$FileName
    )
    $pattern = '(?m)^([A-Fa-f0-9]{64})\s+' + [regex]::Escape($FileName) + '\s*$'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value.ToLowerInvariant()
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
$raw = [System.IO.File]::ReadAllText($manifestPath, $utf8)

$versionMatch = [regex]::Match($raw, '"version":\s*"([^"]+)"')
if (-not $versionMatch.Success) {
    throw 'Could not read "version" from the manifest.'
}
$currentVersion = $versionMatch.Groups[1].Value

Write-Step "Querying $apiUrl"
$release = Get-JsonWithRetry -Uri $apiUrl
if (-not $release.tag) {
    throw 'Release response has no "tag" field.'
}
$tag = [string]$release.tag
$tagMatch = [regex]::Match($tag, '^v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$')
if (-not $tagMatch.Success) {
    throw "Unexpected release tag: $tag"
}
$latestVersion = $tagMatch.Groups[1].Value

$isPrerelease = $false
if ($release.PSObject.Properties.Name -contains 'prerelease') {
    $isPrerelease = [bool]$release.prerelease
}

Write-Host "    manifest: $currentVersion"
Write-Host "    latest:   $latestVersion"
if ($isPrerelease) {
    Write-Host '    note: upstream marks this release as prerelease.' -ForegroundColor Yellow
}

if ($currentVersion -eq $latestVersion -and -not $Force) {
    Write-Host "Already up to date ($currentVersion). Use -Force to re-validate and rewrite." -ForegroundColor Green
    exit 0
}

$zipName = "unc-v$latestVersion-windows-amd64.zip"
$extractDir = "unc-v$latestVersion-windows-amd64"
$zipUrl = "$downloadBase/v$latestVersion/$zipName"
$checksumsUrl = "$downloadBase/v$latestVersion/checksums.txt"

if ($release.PSObject.Properties.Name -contains 'assets') {
    $assets = @($release.assets)
    if ($assets -notcontains $zipName) {
        throw "Release $tag does not list $zipName. Assets: $($assets -join ', ')"
    }
}

$tmp = Join-Path $env:TEMP ('unc-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    Write-Step "Downloading $zipUrl"
    $zipPath = Join-Path $tmp $zipName
    Invoke-DownloadWithRetry -Uri $zipUrl -OutFile $zipPath
    $actualHash = Get-Sha256 -Path $zipPath
    Write-Host "    sha256: $actualHash"

    Write-Step "Fetching $checksumsUrl"
    $checksums = (Invoke-WebRequest -Uri $checksumsUrl -UseBasicParsing -TimeoutSec 30).Content
    $expectedHash = Get-ExpectedHash -Text $checksums -FileName $zipName
    if (-not $expectedHash) {
        throw "checksums.txt has no entry for $zipName"
    }
    Write-Host "    expected: $expectedHash"
    if ($actualHash -ne $expectedHash) {
        throw 'SHA256 mismatch: the downloaded zip differs from checksums.txt.'
    }
    Write-Host '    hash matches checksums.txt' -ForegroundColor Green

    Write-Step 'Checking archive layout'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryName = "$extractDir/unc.exe"
        $entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
        if (-not $entry) {
            $first = @($archive.Entries | Select-Object -First 10 | ForEach-Object { $_.FullName })
            throw "Archive does not contain $entryName. First entries: $($first -join ', ')"
        }
        Write-Host "    found $entryName" -ForegroundColor Green
    } finally {
        $archive.Dispose()
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$newRaw = $raw
$newRaw = $newRaw.Replace('"version": "' + $currentVersion + '"', '"version": "' + $latestVersion + '"')
$newRaw = $newRaw.Replace('/v' + $currentVersion + '/', '/v' + $latestVersion + '/')
$newRaw = $newRaw.Replace('unc-v' + $currentVersion + '-windows-amd64', 'unc-v' + $latestVersion + '-windows-amd64')
$hashRegex = [regex]'"hash":\s*"[0-9a-fA-F]{64}"'
$newRaw = $hashRegex.Replace($newRaw, '"hash": "' + $actualHash + '"', 1)

$newJson = $newRaw | ConvertFrom-Json
$newArch = $newJson.architecture.'64bit'
if ($newJson.version -ne $latestVersion) {
    throw 'Failed to replace "version" in the manifest.'
}
if ($newArch.hash -ne $actualHash) {
    throw 'Failed to replace the static "hash" in the manifest.'
}
if ($newArch.extract_dir -ne $extractDir) {
    throw 'Failed to replace "extract_dir" in the manifest.'
}
if ($newArch.url -ne $zipUrl) {
    throw 'Failed to replace the static "url" in the manifest.'
}

if ($DryRun) {
    Write-Host ''
    Write-Host "Dry run: would update $currentVersion -> $latestVersion" -ForegroundColor Yellow
    Write-Host "    url:         $zipUrl"
    Write-Host "    hash:        $actualHash"
    Write-Host "    extract_dir: $extractDir"
    Write-Host 'Manifest not modified.' -ForegroundColor Yellow
    exit 0
}

Write-Step "Updating $manifestPath"
[System.IO.File]::WriteAllText($manifestPath, $newRaw, $utf8)
Write-Host "    $currentVersion -> $latestVersion" -ForegroundColor Green

if (-not $SkipVerify) {
    Write-Step 'Running verify-manifest.ps1'
    $verifyScript = Join-Path $scriptDir 'verify-manifest.ps1'
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $hostExe = Join-Path $PSHOME 'pwsh.exe'
    } else {
        $hostExe = Join-Path $PSHOME 'powershell.exe'
    }
    $verify = Start-Process -FilePath $hostExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifyScript, '-ManifestPath', $manifestPath
    ) -Wait -PassThru -NoNewWindow
    if ($verify.ExitCode -ne 0) {
        [System.IO.File]::WriteAllText($manifestPath, $raw, $utf8)
        Write-Host 'Verification failed; the manifest was restored.' -ForegroundColor Red
        exit 1
    }
}

Write-Host ''
Write-Host 'Review the diff, then commit and push:' -ForegroundColor Green
Write-Host "    git -C `"$repoRoot`" diff -- bucket/unc.json"
Write-Host "    git -C `"$repoRoot`" pull --ff-only"
Write-Host "    git -C `"$repoRoot`" add bucket/unc.json"
Write-Host "    git -C `"$repoRoot`" commit -m `"unc: Update to version $latestVersion`""
Write-Host "    git -C `"$repoRoot`" push origin master"
exit 0
