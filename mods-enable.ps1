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
New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null

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

$mods = New-Object System.Collections.Generic.List[object]
foreach ($f in @(Get-ChildItem -LiteralPath $DisabledDir -Filter '*.jar' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $meta = Get-FabricModInfo $f.FullName
    $name = '(未知)'
    $id = ''
    $version = ''
    if ($meta) {
        if ($meta.name) { $name = [string]$meta.name }
        elseif ($meta.id) { $name = [string]$meta.id }
        if ($meta.id) { $id = [string]$meta.id }
        if ($meta.version) { $version = [string]$meta.version }
    }
    $mods.Add([pscustomobject]@{
        '模组' = $name
        '版本' = $version
        '文件' = $f.Name
        'ID'   = $id
        'Path' = $f.FullName
    })
}

if ($mods.Count -eq 0) {
    Write-Tip 'mods-disabled 目录里没有可重新启用的模组。'
    exit 0
}

Write-Host ''
Write-Host '已禁用的模组：' -ForegroundColor Cyan
Write-Host ''
for ($i = 0; $i -lt $mods.Count; $i++) {
    $m = $mods[$i]
    Write-Host ("  [{0}] {1} {2}" -f ($i + 1), $m.'模组', $m.'版本')
    Write-Host ("      {0}" -f $m.'文件') -ForegroundColor DarkGray
}
Write-Host ''

$selection = @()
if ($Items -and $Items.Count -gt 0) {
    $selection = @($Items)
}
else {
    $line = Read-Host '输入要重新启用的编号（多个用逗号分隔，直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($line)) {
        Write-Tip '已取消。'
        exit 0
    }
    $selection = @($line -split '[,，\s]+' | Where-Object { $_ })
}

$selected = New-Object System.Collections.Generic.List[object]
$seen = @{}
foreach ($item in $selection) {
    $item = ([string]$item).Trim()
    if ([string]::IsNullOrWhiteSpace($item)) { continue }
    $match = $null
    if ($item -match '^\d+$') {
        $index = [int]$item
        if ($index -ge 1 -and $index -le $mods.Count) {
            $match = $mods[$index - 1]
        }
        else {
            Write-Fail "编号超出范围：$item"
            continue
        }
    }
    else {
        $match = $mods | Where-Object {
            $_.'文件' -ieq $item -or
            $_.'文件' -ieq ($item + '.jar') -or
            $_.'ID' -ieq $item -or
            $_.'模组' -ieq $item
        } | Select-Object -First 1
    }
    if (-not $match) {
        Write-Fail "没有找到模组：$item"
        continue
    }
    if (-not $seen.ContainsKey($match.'Path')) {
        $seen[$match.'Path'] = $true
        $selected.Add($match)
    }
}

if ($selected.Count -eq 0) {
    Write-Tip '没有选择任何模组。'
    exit 0
}

$enabledCount = 0
foreach ($m in $selected) {
    $dest = Join-Path $ModsDir $m.'文件'
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        $backup = Join-Path $DisabledDir ($m.'文件' + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
        Move-Item -LiteralPath $dest -Destination $backup -Force
        Write-Tip "mods 里已有同名文件，旧文件已备份：$($m.'文件')"
    }
    Move-Item -LiteralPath $m.'Path' -Destination $dest -Force
    Write-Ok "已启用：$($m.'文件')"
    $enabledCount++
}

Write-Host ''
if ($enabledCount -gt 0) {
    Write-Ok "本次重新启用 $enabledCount 个模组。"
    if (Test-ServerRunning) {
        Write-Tip '服务器正在运行，需要重启后才会生效：先运行 stop.bat，再运行 start.bat。'
    }
    else {
        Write-Tip '下次运行 start.bat 时生效。'
    }
}
