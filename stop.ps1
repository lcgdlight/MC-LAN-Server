#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
try { $Host.UI.RawUI.WindowTitle = '停止 Minecraft 服务器' } catch { }

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Rcon.ps1')

$propsPath = Join-Path $Root 'server.properties'
$pidFile = Join-Path $Root 'run\server.pid'
$rconInfoPath = Join-Path $Root 'run\rcon.txt'

$rconInfo = @{}
if (Test-Path -LiteralPath $rconInfoPath -PathType Leaf) {
    $rconInfo = Read-McEnvFile -Path $rconInfoPath
}

$serverPort = 25565
$rconPort = 25575
$rconPassword = ''
if ($rconInfo['SERVER_PORT'] -match '^\d+$') { $serverPort = [int]$rconInfo['SERVER_PORT'] }
if ($rconInfo['RCON_PORT'] -match '^\d+$') { $rconPort = [int]$rconInfo['RCON_PORT'] }
if ($rconInfo['RCON_PASSWORD']) { $rconPassword = [string]$rconInfo['RCON_PASSWORD'] }

if (Test-Path -LiteralPath $propsPath -PathType Leaf) {
    try {
        $props = Read-McProperties -Path $propsPath
        if ([string]::IsNullOrWhiteSpace($rconPassword) -and $props['rcon.password']) {
            $rconPassword = [string]$props['rcon.password']
        }
        if ($props['server-port'] -match '^\d+$') { $serverPort = [int]$props['server-port'] }
        if ($props['rcon.port'] -match '^\d+$') { $rconPort = [int]$props['rcon.port'] }
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($rconPassword)) {
            Write-McError "无法读取 server.properties：$($_.Exception.Message)"
            Write-McInfo '请关闭占用该文件的程序，或先运行 start.bat 生成 run\rcon.txt。'
            exit 1
        }
        Write-McWarn 'server.properties 正被服务器占用，已改用 run\rcon.txt 中的连接信息。'
    }
}
elseif (-not $rconInfo -or [string]::IsNullOrWhiteSpace($rconPassword)) {
    Write-McError '未找到 server.properties 或 run\rcon.txt。服务器可能还没有启动过。'
    exit 1
}

$config = Read-McEnvFile -Path (Join-Path $Root 'server.env')
$jarName = 'server.jar'
if ($config['SERVER_JAR']) { $jarName = [string]$config['SERVER_JAR'] }

$pidInfo = Get-McServerProcess -PidFile $pidFile -JarName $jarName
$portInfo = @(Get-McPortInfo -Port $serverPort)

if (-not $pidInfo -and $portInfo.Count -eq 0) {
    Write-McInfo '服务器当前没有运行，不需要停止。'
    if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

Write-McTitle '停止 Minecraft 服务器'
if ($pidInfo) {
    Write-McInfo "服务器进程：PID $($pidInfo.Id)"
}
else {
    Write-McInfo '未找到 PID 文件，但端口仍在监听；将尝试直接通过 RCON 停止。'
}
Write-McInfo "服务器端口：$serverPort；管理端口：127.0.0.1:$rconPort"

if ([string]::IsNullOrWhiteSpace($rconPassword)) {
    Write-McError 'server.properties 中没有 RCON 密码，无法安全停止服务器。'
    Write-McInfo '请先双击 start.bat 启动一次，让脚本自动补全 RCON 配置；或到服务器窗口输入 stop。'
    exit 1
}

$session = $null
$lastError = ''
for ($i = 1; $i -le 60; $i++) {
    try {
        $session = Connect-McRcon -Port $rconPort -Password $rconPassword -TimeoutMs 2000
        break
    }
    catch {
        $lastError = $_.Exception.Message
        if ($lastError -match '密码') { break }
        if ($i -eq 1) {
            Write-McInfo '正在等待服务器控制台就绪（服务器可能还在启动）...'
        }
        if ($i % 10 -eq 0) {
            Write-McInfo "仍在等待 RCON 响应（$i/60 秒）..."
        }
        Start-Sleep -Milliseconds 1000
    }
}

if ($session) {
    Write-McOk '已连接服务器控制台（RCON）。'
    Write-McInfo '正在保存世界并发送 stop 指令...'
    try {
        Invoke-McRconStop -Session $session
    }
    catch {
        Write-McWarn "发送 stop 时出现异常：$($_.Exception.Message)"
    }
    finally {
        Close-McRcon -Session $session
    }
    Write-McOk '已发送安全停止指令，正在等待服务器退出并保存存档...'
}
else {
    Write-McError "无法通过 RCON 停止服务器：$lastError"

    if ($Force) {
        if (-not $pidInfo) {
            Write-McError '找不到服务器 Java 进程的 PID，无法执行强制结束。请到服务器窗口输入 stop。'
            exit 1
        }
        Write-McWarn '即将强制结束 Java 进程。世界可能没有保存，存在存档损坏风险。'
        Write-McWarn '如要取消，请在 5 秒内按 Ctrl+C。'
        Start-Sleep -Seconds 5
        try {
            Stop-Process -Id $pidInfo.Id -Force -ErrorAction Stop
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            Write-McWarn '已强制结束服务器进程。建议下次启动前先备份世界文件夹。'
            exit 0
        }
        catch {
            Write-McError "强制结束失败：$($_.Exception.Message)"
            exit 1
        }
    }

    Write-McInfo '请切换到服务器窗口，输入 stop 并回车。不要直接点击窗口右上角关闭。'
    Write-McInfo '如果服务器窗口已经无响应，可运行：powershell -ExecutionPolicy Bypass -File .\stop.ps1 -Force'
    exit 1
}

$waited = 0
$stillRunning = $true
while ($waited -lt 90) {
    $stillRunning = $false
    if ($pidInfo) {
        $proc = Get-Process -Id $pidInfo.Id -ErrorAction SilentlyContinue
        if ($proc) { $stillRunning = $true }
    }
    if (-not $stillRunning) {
        $remainingPorts = @(Get-McPortInfo -Port $serverPort)
        if ($remainingPorts.Count -gt 0) { $stillRunning = $true }
    }
    if (-not $stillRunning) { break }
    Start-Sleep -Seconds 1
    $waited++
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue

if ($stillRunning) {
    Write-McError '等待 90 秒后服务器仍在运行。'
    Write-McInfo '请查看服务器窗口是否卡住；不要直接关闭窗口。可尝试再次运行 stop.bat。'
    exit 1
}

Write-McOk '服务器已安全停止，世界和配置已保存。'
Write-McInfo '下次双击 start.bat 即可继续使用原来的世界和配置。'
exit 0
