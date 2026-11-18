#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
try { $Host.UI.RawUI.WindowTitle = '备份 Minecraft 服务器' } catch { }

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Rcon.ps1')

Write-McTitle '备份 Minecraft 服务器'
Write-McInfo '备份过程中请不要关闭此窗口；世界较大时可能需要几十秒。'

$config = Read-McEnvFile -Path (Join-Path $Root 'server.env')
$jarName = 'server.jar'
if ($config['SERVER_JAR']) { $jarName = [string]$config['SERVER_JAR'] }

$serverPort = 25565
$rconPort = 25575
$propsPath = Join-Path $Root 'server.properties'
$rconInfoPath = Join-Path $Root 'run\rcon.txt'

$rconInfo = @{}
if (Test-Path -LiteralPath $rconInfoPath -PathType Leaf) {
    $rconInfo = Read-McEnvFile -Path $rconInfoPath
}
if ($rconInfo['SERVER_PORT'] -match '^\d+$') { $serverPort = [int]$rconInfo['SERVER_PORT'] }
if ($rconInfo['RCON_PORT'] -match '^\d+$') { $rconPort = [int]$rconInfo['RCON_PORT'] }
$rconPassword = ''
if ($rconInfo['RCON_PASSWORD']) { $rconPassword = [string]$rconInfo['RCON_PASSWORD'] }

$props = @{}
if (Test-Path -LiteralPath $propsPath -PathType Leaf) {
    try {
        $props = Read-McProperties -Path $propsPath
        if ($props['server-port'] -match '^\d+$') { $serverPort = [int]$props['server-port'] }
        if ($props['rcon.port'] -match '^\d+$') { $rconPort = [int]$props['rcon.port'] }
        if ([string]::IsNullOrWhiteSpace($rconPassword) -and $props['rcon.password']) {
            $rconPassword = [string]$props['rcon.password']
        }
    }
    catch {
        if ($rconInfo.Count -eq 0) {
            Write-McError "无法读取 server.properties：$($_.Exception.Message)"
            exit 1
        }
    }
}

$pidInfo = Get-McServerProcess -PidFile (Join-Path $Root 'run\server.pid') -JarName $jarName
$portInfo = @(Get-McPortInfo -Port $serverPort)
$isRunning = [bool]($pidInfo -or $portInfo.Count -gt 0)

$backupDir = Join-Path $Root 'backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$finalPath = Join-Path $backupDir "mc-backup-$timestamp.zip"
$suffix = 1
while (Test-Path -LiteralPath $finalPath -PathType Leaf) {
    $finalPath = Join-Path $backupDir "mc-backup-$timestamp-($suffix).zip"
    $suffix++
}
$tempPath = Join-Path $backupDir ('.backup-' + [guid]::NewGuid().ToString('N') + '.tmp')

$items = @(
    [pscustomobject]@{ Relative = 'world'; IsDirectory = $true },
    [pscustomobject]@{ Relative = 'plugins'; IsDirectory = $true },
    [pscustomobject]@{ Relative = 'config'; IsDirectory = $true },
    [pscustomobject]@{ Relative = 'server.properties'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'server.env'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'eula.txt'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'ops.json'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'whitelist.json'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'banned-players.json'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'banned-ips.json'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'bukkit.yml'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'spigot.yml'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'commands.yml'; IsDirectory = $false },
    [pscustomobject]@{ Relative = 'server-info.txt'; IsDirectory = $false }
)

$files = New-Object 'System.Collections.Generic.List[object]'
$totalBytes = [long]0
foreach ($item in $items) {
    $fullPath = Join-Path $Root $item.Relative
    if (-not (Test-Path -LiteralPath $fullPath)) { continue }
    if ($item.IsDirectory) {
        $children = @(Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction Stop)
        foreach ($file in $children) {
            if ($file.Name -ieq 'session.lock') { continue }
            $rel = $file.FullName.Substring($Root.Length).TrimStart('\')
            $files.Add([pscustomobject]@{ FullName = $file.FullName; Relative = $rel })
            $totalBytes += $file.Length
        }
    }
    else {
        $file = Get-Item -LiteralPath $fullPath -ErrorAction Stop
        $rel = $file.FullName.Substring($Root.Length).TrimStart('\')
        $files.Add([pscustomobject]@{ FullName = $file.FullName; Relative = $rel })
        $totalBytes += $file.Length
    }
}

if ($files.Count -eq 0) {
    Write-McError '没有找到可备份的世界或配置文件。请确认 server.env 和世界目录完整。'
    exit 1
}

try {
    $driveRoot = [System.IO.Path]::GetPathRoot($backupDir)
    $drive = New-Object System.IO.DriveInfo($driveRoot)
    $freeBytes = [long]$drive.AvailableFreeSpace
    $requiredBytes = $totalBytes + 64MB
    if ($freeBytes -lt $requiredBytes) {
        throw "备份所在磁盘空间不足：需要至少 $([math]::Round($requiredBytes / 1MB, 1)) MB，可用 $([math]::Round($freeBytes / 1MB, 1)) MB。"
    }
}
catch [System.ArgumentException] {
    # 网络路径等无法通过 DriveInfo 获取空间时继续，打包失败会给出明确错误。
}
catch {
    if ($_.Exception.Message -like '备份所在磁盘空间不足*') { Write-McError $_.Exception.Message; exit 1 }
}

Write-McInfo "备份文件：$finalPath"
Write-McInfo "待打包：$($files.Count) 个文件，约 $([math]::Round($totalBytes / 1MB, 1)) MB"

function Add-McZipEntryFromFile {
    param(
        [Parameter(Mandatory = $true)]$Archive,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )
    # 运行中的服务器会以可写方式占用部分配置文件；读取时允许共享写入，避免备份被误判为失败。
    $source = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $entry = $null
    try {
        $entry = $Archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
        try { $entry.LastWriteTime = [System.IO.File]::GetLastWriteTime($SourcePath) } catch { }
        $destination = $entry.Open()
        try {
            $source.CopyTo($destination)
        }
        finally {
            $destination.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }
}

$session = $null
$savingDisabled = $false
$backupSucceeded = $false
try {
    if ($isRunning) {
        if ([string]::IsNullOrWhiteSpace($rconPassword)) {
            throw '服务器正在运行，但找不到 RCON 密码，无法暂停保存。请先双击 stop.bat 停止服务器后再备份。'
        }

        Write-McInfo '服务器正在运行，正在通过 RCON 暂停自动保存并刷盘...'
        $session = Connect-McRcon -Port $rconPort -Password $rconPassword -TimeoutMs 5000
        $savingDisabled = $true
        $offReply = Invoke-McRconCommand -Session $session -Command 'save-off' -TimeoutMs 15000
        if ($offReply) { Write-McInfo $offReply }
        $flush = Invoke-McRconCommand -Session $session -Command 'save-all flush' -TimeoutMs 60000
        if ($flush) { Write-McInfo $flush }
        Write-McOk '世界已刷盘，自动保存已暂停；开始打包。'
    }
    else {
        Write-McInfo '服务器当前未运行，将直接读取磁盘文件打包。'
    }

    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    $stream = [System.IO.File]::Open($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $archive = $null
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
        foreach ($file in $files) {
            $entryName = $file.Relative -replace '\\', '/'
            Add-McZipEntryFromFile -Archive $archive -SourcePath $file.FullName -EntryName $entryName
        }
    }
    finally {
        if ($archive) { $archive.Dispose() }
        if ($stream) { $stream.Dispose() }
    }

    if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
        throw '备份临时文件没有生成。'
    }
    $tempSize = (Get-Item -LiteralPath $tempPath).Length
    if ($tempSize -le 0) {
        throw '备份文件为空。'
    }
    Move-Item -LiteralPath $tempPath -Destination $finalPath -Force
    $backupSucceeded = $true
}
catch {
    Write-McError "备份失败：$($_.Exception.Message)"
}
finally {
    if ($savingDisabled -and $session) {
        try {
            $onReply = Invoke-McRconCommand -Session $session -Command 'save-on' -TimeoutMs 15000
            if ($onReply) { Write-McInfo $onReply }
            Write-McOk '已恢复服务器自动保存。'
        }
        catch {
            Write-McError "未能恢复自动保存：$($_.Exception.Message)"
            Write-McInfo '请到服务器窗口输入 save-on 恢复自动保存，避免存档长时间不落盘。'
        }
    }
    if ($session) { Close-McRcon -Session $session }
    if (-not $backupSucceeded -and (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
}

if (-not $backupSucceeded) {
    exit 1
}

$backupFile = Get-Item -LiteralPath $finalPath
Write-McOk "备份完成：$($backupFile.FullName)"
Write-McInfo "大小：$([math]::Round($backupFile.Length / 1MB, 2)) MB；包含 $($files.Count) 个文件。"
Write-McInfo '恢复备份前请先 stop.bat；不要把备份解压覆盖到正在运行的服务器目录。'
exit 0
