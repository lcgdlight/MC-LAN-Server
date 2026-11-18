#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Version = '',
    [switch]$Vanilla,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

. (Join-Path $Root 'lib\Common.ps1')

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

Write-McTitle '下载 Minecraft 服务端'

$config = Read-McEnvFile -Path (Join-Path $Root 'server.env')
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = '26.3'
    if ($config['MC_VERSION']) { $Version = [string]$config['MC_VERSION'] }
}

$pidFile = Join-Path $Root 'run\server.pid'
$jarName = 'server.jar'
if ($config['SERVER_JAR']) { $jarName = [string]$config['SERVER_JAR'] }
$running = Get-McServerProcess -PidFile $pidFile -JarName $jarName
if ($running) {
    Write-McError "服务器正在运行（PID $($running.Id)），不能替换 server.jar。"
    Write-McInfo '请先双击 stop.bat 停止服务器，再下载。'
    exit 1
}

$jarPath = $jarName
if (-not [System.IO.Path]::IsPathRooted($jarPath)) { $jarPath = Join-Path $Root $jarPath }
if ((Test-Path -LiteralPath $jarPath -PathType Leaf) -and -not $Force) {
    $answer = Read-Host "server.jar 已存在（$([math]::Round((Get-Item $jarPath).Length / 1MB, 1)) MB）。是否重新下载并覆盖？原文件会备份 (Y/N)"
    if ($answer -notmatch '^[Yy]') {
        Write-McInfo '已取消下载。'
        exit 0
    }
}

$headers = @{ 'User-Agent' = 'MC-LAN-Server/1.0 (Windows local setup)' }
$downloadUrl = $null
$sha256 = $null
$sha1 = $null
$expectedSize = 0
$build = ''
$channel = ''
$fileName = ''
$type = ''

try {
    if ($Vanilla) {
        Write-McInfo "正在查询 Mojang 官方服务端版本 $Version ..."
        $manifest = Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -Headers $headers -TimeoutSec 30
        $entry = $manifest.versions | Where-Object { $_.id -eq $Version } | Select-Object -First 1
        if (-not $entry) { throw "Mojang 版本清单中没有 Minecraft $Version。" }
        $versionJson = Invoke-RestMethod -Uri $entry.url -Headers $headers -TimeoutSec 30
        if (-not $versionJson.downloads.server) { throw "Minecraft $Version 没有官方服务端下载。" }
        $downloadUrl = [string]$versionJson.downloads.server.url
        $sha1 = [string]$versionJson.downloads.server.sha1
        $expectedSize = [long]$versionJson.downloads.server.size
        $fileName = "minecraft_server.$Version.jar"
        $type = 'Vanilla'
    }
    else {
        Write-McInfo "正在查询 Paper $Version 的最新构建 ..."
        $apiUrl = "https://fill.papermc.io/v3/projects/paper/versions/$Version/builds/latest"
        try {
            $meta = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30
        }
        catch {
            $versions = @()
            try {
                $project = Invoke-RestMethod -Uri 'https://fill.papermc.io/v3/projects/paper' -Headers $headers -TimeoutSec 30
                $versions = @($project.versions.PSObject.Properties.Name)
            }
            catch { }
            $hint = ''
            if ($versions.Count -gt 0) {
                $hint = ' 可用版本示例：' + (($versions | Select-Object -First 8) -join '、')
            }
            throw "Paper 没有找到 Minecraft $Version 的构建。$hint 也可以运行 download-server.bat -Vanilla 下载官方原版服务端。"
        }
        $dl = $meta.downloads.'server:default'
        if (-not $dl) { throw 'Paper API 返回的数据中没有 server:default 下载项。' }
        $downloadUrl = [string]$dl.url
        $sha256 = [string]$dl.checksums.sha256
        $expectedSize = [long]$dl.size
        $build = [string]$meta.id
        $channel = [string]$meta.channel
        $fileName = [string]$dl.name
        $type = 'Paper'
    }
}
catch {
    Write-McError $_.Exception.Message
    exit 1
}

Write-McInfo "类型：$type；Minecraft：$Version；构建：$build；通道：$channel"
if ($expectedSize -gt 0) { Write-McInfo "大小：$([math]::Round($expectedSize / 1MB, 1)) MB" }

$runDir = Join-Path $Root 'run'
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$tempFile = Join-Path $runDir 'server.jar.download'
Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue

try {
    Write-McInfo '正在下载，请保持网络连接 ...'
    Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $tempFile -Headers $headers -TimeoutSec 600
}
catch {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    Write-McError "下载失败：$($_.Exception.Message)"
    Write-McInfo "也可以手动下载并保存为：$jarPath"
    exit 1
}

try {
    if (-not (Test-Path -LiteralPath $tempFile -PathType Leaf)) { throw '下载文件不存在。' }
    $actualSize = (Get-Item -LiteralPath $tempFile).Length
    Write-McInfo "下载完成：$([math]::Round($actualSize / 1MB, 1)) MB，正在校验 ..."
    if ($expectedSize -gt 0 -and $actualSize -ne $expectedSize) {
        throw "文件大小不一致：期望 $expectedSize 字节，实际 $actualSize 字节。"
    }
    if ($sha256) {
        $actualHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $sha256.ToLowerInvariant()) { throw "SHA256 校验失败。期望 $sha256，实际 $actualHash。" }
        Write-McOk 'SHA256 校验通过。'
    }
    elseif ($sha1) {
        $actualHash = (Get-FileHash -LiteralPath $tempFile -Algorithm SHA1).Hash.ToLowerInvariant()
        if ($actualHash -ne $sha1.ToLowerInvariant()) { throw "SHA1 校验失败。期望 $sha1，实际 $actualHash。" }
        Write-McOk 'SHA1 校验通过。'
    }
}
catch {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    Write-McError $_.Exception.Message
    exit 1
}

try {
    if (Test-Path -LiteralPath $jarPath -PathType Leaf) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $Root ("server.jar.bak-$stamp")
        Copy-Item -LiteralPath $jarPath -Destination $backup -Force
        Write-McInfo "旧服务端已备份：$backup"
    }
    Move-Item -LiteralPath $tempFile -Destination $jarPath -Force
}
catch {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    Write-McError "保存 server.jar 失败：$($_.Exception.Message)"
    Write-McInfo '如果服务器正在运行，请先 stop.bat。文件被占用时请关闭资源管理器预览或杀毒扫描。'
    exit 1
}

$size = (Get-Item -LiteralPath $jarPath).Length
$infoLines = @(
    "TYPE=$type",
    "MC_VERSION=$Version",
    "BUILD=$build",
    "CHANNEL=$channel",
    "FILE=$fileName",
    "SIZE=$size",
    "SHA256=$sha256",
    "SHA1=$sha1",
    "DOWNLOADED=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
)
[System.IO.File]::WriteAllText((Join-Path $Root 'server-info.txt'), (($infoLines -join "`r`n") + "`r`n"), $Utf8NoBom)

Write-McOk "服务端已保存：$jarPath"
Write-McInfo '接下来：1) 双击 firewall.bat 放行防火墙；2) 双击 start.bat 启动服务器。'
if ($type -eq 'Paper') {
    Write-McInfo 'Paper 支持 Bukkit/Spigot/Paper 插件，客户端不需要安装任何模组。'
}
exit 0
