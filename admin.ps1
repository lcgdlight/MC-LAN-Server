#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Command)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Rcon.ps1')

$propsPath = Join-Path $Root 'server.properties'
$rconInfoPath = Join-Path $Root 'run\rcon.txt'

$rconInfo = @{}
if (Test-Path -LiteralPath $rconInfoPath -PathType Leaf) {
    $rconInfo = Read-McEnvFile -Path $rconInfoPath
}

$rconPort = 25575
$rconPassword = ''
if ($rconInfo['RCON_PORT'] -match '^\d+$') { $rconPort = [int]$rconInfo['RCON_PORT'] }
if ($rconInfo['RCON_PASSWORD']) { $rconPassword = [string]$rconInfo['RCON_PASSWORD'] }

if (Test-Path -LiteralPath $propsPath -PathType Leaf) {
    try {
        $props = Read-McProperties -Path $propsPath
        if ([string]::IsNullOrWhiteSpace($rconPassword) -and $props['rcon.password']) {
            $rconPassword = [string]$props['rcon.password']
        }
        if ($props['rcon.port'] -match '^\d+$') { $rconPort = [int]$props['rcon.port'] }
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($rconPassword)) {
            Write-McError "无法读取 server.properties：$($_.Exception.Message)"
            Write-McInfo '请确认服务器已经启动，或先运行 start.bat 生成 run\rcon.txt。'
            exit 1
        }
        Write-McWarn 'server.properties 正被服务器占用，已改用 run\rcon.txt 中的连接信息。'
    }
}
elseif (-not $rconInfo) {
    Write-McError '未找到 server.properties 或 run\rcon.txt。请先启动一次服务器。'
    exit 1
}

if ([string]::IsNullOrWhiteSpace($rconPassword)) {
    Write-McError '没有找到 RCON 密码。请先运行 start.bat 让脚本自动补全。'
    exit 1
}

$session = $null
try {
    $session = Connect-McRcon -Port $rconPort -Password $rconPassword -TimeoutMs 5000
}
catch {
    Write-McError "无法连接服务器 RCON：$($_.Exception.Message)"
    Write-McInfo '请确认服务器已经启动，并且没有关闭 RCON。'
    exit 1
}

try {
    if ($Command -and $Command.Count -gt 0) {
        $line = ($Command -join ' ').Trim()
        if ($line.Length -eq 0) { exit 0 }
        $output = Invoke-McRconCommand -Session $session -Command $line -TimeoutMs 15000
        if ([string]::IsNullOrWhiteSpace($output)) {
            Write-Host '（命令已执行，无返回内容）' -ForegroundColor DarkGray
        }
        else {
            Write-Host $output
        }
        exit 0
    }

    Write-McTitle 'Minecraft 管理员控制台（RCON）'
    Write-McInfo '输入 Minecraft 控制台命令，例如：list / say 大家好 / op 玩家名 / whitelist add 玩家名'
    Write-McInfo '输入 exit 退出控制台（不会关闭服务器）。停止服务器请用 stop.bat。'
    Write-Host ''

    while ($true) {
        $line = Read-Host '服务器'
        if ($null -eq $line) { break }
        $line = $line.Trim()
        if ($line.Length -eq 0) { continue }
        if ($line -in @('exit', 'quit', '.exit', ':q')) { break }

        if ($line -match '^stop$') {
            $confirm = Read-Host '这会停止服务器。确认请输入 YES'
            if ($confirm -ne 'YES') {
                Write-McInfo '已取消。'
                continue
            }
        }

        try {
            $output = Invoke-McRconCommand -Session $session -Command $line -TimeoutMs 15000
            if ([string]::IsNullOrWhiteSpace($output)) {
                Write-Host '（命令已执行，无返回内容）' -ForegroundColor DarkGray
            }
            else {
                Write-Host $output
            }
        }
        catch {
            Write-McError "命令执行失败：$($_.Exception.Message)"
            break
        }

        if ($line -match '^stop$') { break }
    }
}
finally {
    Close-McRcon -Session $session
}

Write-McInfo '已退出管理员控制台。'
exit 0
