#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ModsDir = Join-Path $Root 'mods'
$DisabledDir = Join-Path $Root 'mods-disabled'

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

function New-ModRow([System.IO.FileInfo]$File, [string]$Status) {
    $meta = Get-FabricModInfo $File.FullName
    $name = '(未知)'
    $id = ''
    $version = ''
    if ($meta) {
        if ($meta.name) { $name = [string]$meta.name }
        elseif ($meta.id) { $name = [string]$meta.id }
        if ($meta.id) { $id = [string]$meta.id }
        if ($meta.version) { $version = [string]$meta.version }
    }
    return [pscustomobject]@{
        '状态'   = $Status
        '模组'   = $name
        '版本'   = $version
        '文件'   = $File.Name
        '大小KB' = [math]::Round($File.Length / 1KB, 1)
        'ID'     = $id
        'Path'   = $File.FullName
    }
}

$rows = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $ModsDir -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $ModsDir -Filter '*.jar' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $rows.Add((New-ModRow $f '启用'))
    }
}
if (Test-Path -LiteralPath $DisabledDir -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $DisabledDir -Filter '*.jar' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $rows.Add((New-ModRow $f '禁用'))
    }
}

$serverType = 'Fabric'
$mcVersion = '26.3'
$loader = ''
$infoPath = Join-Path $Root 'server-info.txt'
if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $infoPath -ErrorAction SilentlyContinue) {
        if ($line -match '^([^=]+)=(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            if ($key -eq 'TYPE') { $serverType = $value }
            if ($key -eq 'MC_VERSION') { $mcVersion = $value }
            if ($key -eq 'BUILD') { $loader = $value }
        }
    }
}

$serverLine = "服务器：$serverType $mcVersion"
if ($loader) { $serverLine += " / Fabric Loader $loader" }

Write-Host ''
Write-Host $serverLine -ForegroundColor Cyan
Write-Host "模组目录：$ModsDir"
Write-Host "禁用目录：$DisabledDir"
Write-Host ''

if ($rows.Count -eq 0) {
    Write-Host '还没有安装任何模组。把 .jar 拖到 mods-add.bat 上即可添加。' -ForegroundColor Yellow
    exit 0
}

$active = ($rows | Where-Object { $_.'状态' -eq '启用' } | Measure-Object).Count
$disabled = ($rows | Where-Object { $_.'状态' -eq '禁用' } | Measure-Object).Count
Write-Host "启用 $active 个，禁用 $disabled 个：" -ForegroundColor Green
Write-Host ''
$rows | Select-Object `
    @{ Name = 'Status'; Expression = { $_.'状态' } }, `
    @{ Name = 'Mod'; Expression = { $_.'模组' } }, `
    @{ Name = 'Version'; Expression = { $_.'版本' } }, `
    @{ Name = 'File'; Expression = { $_.'文件' } }, `
    @{ Name = 'KB'; Expression = { $_.'大小KB' } } |
    Format-Table -AutoSize | Out-String -Width 240 | Write-Host
Write-Host '添加：把 jar 拖到 mods-add.bat；禁用：运行 mods-remove.bat；打开目录：mods-folder.bat' -ForegroundColor DarkGray
