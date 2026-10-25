#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Items)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ModsDir = Join-Path $Root 'mods'
$DisabledDir = Join-Path $Root 'mods-disabled'
New-Item -ItemType Directory -Force -Path $ModsDir, $DisabledDir | Out-Null

function Write-Step([string]$Text) { Write-Host "[模组] $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "[完成] $Text" -ForegroundColor Green }
function Write-Tip([string]$Text) { Write-Host "[提示] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "[错误] $Text" -ForegroundColor Red }

function Test-ServerRunning {
    $pidFile = Join-Path $Root 'run\server.pid'
    if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
        $text = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue)
        if ($null -ne $text) { $text = $text.Trim() }
        if ($text -match '^\d+$') {
            return [bool](Get-Process -Id ([int]$text) -ErrorAction SilentlyContinue)
        }
    }
    return $false
}

function Get-FabricModInfo([string]$JarPath) {
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)
        $entry = $zip.GetEntry('fabric.mod.json')
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return ($json | ConvertFrom-Json)
    }
    catch {
        return $null
    }
    finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Resolve-Modrinth([string]$Url) {
    if ($Url -notmatch '^https?://(?:www\.)?modrinth\.com/mod/([^/?#]+)(?:/version/([^/?#]+))?') { return $null }
    $slug = $Matches[1]
    $versionId = $Matches[2]
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{ 'User-Agent' = 'MC-LAN-Server-ModHelper/1.0' }
        if ($versionId) {
            $data = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/$slug/version/$versionId" -Headers $headers -TimeoutSec 30
            $versions = @($data)
        }
        else {
            $data = Invoke-RestMethod -Uri "https://api.modrinth.com/v2/project/$slug/version?game_versions=%5B%2226.3%22%5D&loaders=%5B%22fabric%22%5D" -Headers $headers -TimeoutSec 30
            $versions = @($data)
        }
        if ($versions.Count -eq 0) { return $null }
        $v = $versions[0]
        $file = @($v.files | Where-Object { $_.primary }) | Select-Object -First 1
        if (-not $file) { $file = @($v.files)[0] }
        if (-not $file) { return $null }
        return [pscustomobject]@{ Url = [string]$file.url; FileName = [string]$file.filename }
    }
    catch {
        Write-Tip "Modrinth 查询失败：$($_.Exception.Message)"
        return $null
    }
}

function Download-File([string]$Url, [string]$OutFile) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source --ssl-no-revoke -L --retry 3 --retry-delay 2 -s -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "下载失败（curl 退出码 $LASTEXITCODE）" }
    }
    else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
    }
}

function Split-InputLine([string]$Line) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Line, '"([^"]+)"|(\S+)')) {
        if ($m.Groups[1].Success) { $result.Add($m.Groups[1].Value) }
        elseif ($m.Groups[2].Success) { $result.Add($m.Groups[2].Value) }
    }
    return @($result)
}

$inputItems = @()
if ($Items -and $Items.Count -gt 0) {
    $inputItems = @($Items)
}
else {
    Write-Step '把 .jar 文件拖到此窗口，或粘贴下载链接，然后按回车：'
    $line = Read-Host
    if ([string]::IsNullOrWhiteSpace($line)) {
        Write-Tip '没有输入，已取消。'
        exit 0
    }
    $inputItems = Split-InputLine $line
}

$added = 0
foreach ($rawItem in $inputItems) {
    $item = ([string]$rawItem).Trim()
    if ([string]::IsNullOrWhiteSpace($item)) { continue }

    $tmpFile = $null
    $fileName = $null
    try {
        if ($item -match '^https?://') {
            $isModrinth = $item -match '^https?://(?:www\.)?modrinth\.com/'
            $resolved = $null
            if ($isModrinth) { $resolved = Resolve-Modrinth $item }
            if ($isModrinth -and -not $resolved) {
                Write-Fail "无法从 Modrinth 解析该链接（需要 Fabric 26.3 版本）：$item"
                continue
            }

            if ($resolved) {
                $url = $resolved.Url
                $fileName = $resolved.FileName
                Write-Step "从 Modrinth 下载：$fileName"
            }
            else {
                $url = $item
                try { $uri = [Uri]$url } catch { throw '下载链接格式不正确。' }
                $fileName = [IO.Path]::GetFileName($uri.AbsolutePath)
                $fileName = [Uri]::UnescapeDataString($fileName)
                if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName -notmatch '\.jar$') {
                    $fileName = 'mod-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.jar'
                }
                Write-Step "下载：$url"
            }

            $tmpFile = Join-Path $env:TEMP ('mcmod-' + [Guid]::NewGuid().ToString('N') + '.jar')
            Download-File $url $tmpFile
        }
        else {
            $src = $item.Trim('"')
            if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
                Write-Fail "找不到文件：$src"
                continue
            }
            $srcItem = Get-Item -LiteralPath $src
            if ($srcItem.Extension -ne '.jar') {
                Write-Fail "不是 .jar 文件：$($srcItem.Name)"
                continue
            }
            $fileName = $srcItem.Name
            $tmpFile = Join-Path $env:TEMP ('mcmod-' + [Guid]::NewGuid().ToString('N') + '.jar')
            Copy-Item -LiteralPath $srcItem.FullName -Destination $tmpFile -Force
        }

        if (-not (Test-Path -LiteralPath $tmpFile -PathType Leaf)) { throw '下载或复制失败，文件不存在。' }
        if ((Get-Item -LiteralPath $tmpFile).Length -eq 0) { throw '文件为空。' }

        $info = Get-FabricModInfo $tmpFile
        if (-not $info) {
            Write-Tip "这个 jar 里没有 fabric.mod.json，可能不是 Fabric 模组（Forge/NeoForge/插件无法加载）。"
            $answer = Read-Host '仍然添加到 mods 吗？(y/N)'
            if ($answer -notmatch '^[yY]') {
                Write-Tip "已跳过：$fileName"
                continue
            }
        }
        else {
            $modName = if ($info.name) { [string]$info.name } elseif ($info.id) { [string]$info.id } else { '(未知模组)' }
            $modVer = if ($info.version) { [string]$info.version } else { '?' }
            Write-Step "识别到模组：$modName $modVer"
        }

        $dest = Join-Path $ModsDir $fileName
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            $oldHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
            $newHash = (Get-FileHash -LiteralPath $tmpFile -Algorithm SHA256).Hash
            if ($oldHash -eq $newHash) {
                Write-Ok "已存在相同文件，无需重复添加：$fileName"
                Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                continue
            }
            $backupName = $fileName + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
            Move-Item -LiteralPath $dest -Destination (Join-Path $DisabledDir $backupName) -Force
            Write-Tip "旧文件已移到 mods-disabled：$backupName"
        }

        Move-Item -LiteralPath $tmpFile -Destination $dest -Force
        Write-Ok "已添加：$fileName"
        $added++
    }
    catch {
        Write-Fail "$item -> $($_.Exception.Message)"
    }
    finally {
        if ($tmpFile -and (Test-Path -LiteralPath $tmpFile -PathType Leaf)) {
            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ''
if ($added -gt 0) {
    $activeCount = @(Get-ChildItem -LiteralPath $ModsDir -Filter '*.jar' -File -ErrorAction SilentlyContinue).Count
    Write-Ok "本次添加 $added 个模组，当前共 $activeCount 个启用模组。"
    if (Test-ServerRunning) {
        Write-Tip '服务器正在运行，新模组需要重启后才会加载：先运行 stop.bat，再运行 start.bat。'
    }
    else {
        Write-Tip '下次运行 start.bat 时生效。'
    }
}
else {
    Write-Tip '没有添加任何模组。'
}
