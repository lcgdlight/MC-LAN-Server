#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Elevate,
    [switch]$Run,
    [switch]$Remove,
    [switch]$Status,
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false

. (Join-Path $Root 'lib\Common.ps1')

function Test-McAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$config = Read-McEnvFile -Path (Join-Path $Root 'server.env')
if ($Port -le 0) {
    $Port = 25565
    if ($config['SERVER_PORT'] -match '^\d+$') { $Port = [int]$config['SERVER_PORT'] }
}
if ($Port -lt 1 -or $Port -gt 65535) {
    Write-McError "端口无效：$Port"
    exit 1
}

$rconPort = 25575
$rconInfoPath = Join-Path $Root 'run\rcon.txt'
$propsPath = Join-Path $Root 'server.properties'
if (Test-Path -LiteralPath $rconInfoPath -PathType Leaf) {
    $rconInfo = Read-McEnvFile -Path $rconInfoPath
    if ($rconInfo['RCON_PORT'] -match '^\d+$') { $rconPort = [int]$rconInfo['RCON_PORT'] }
}
elseif (Test-Path -LiteralPath $propsPath -PathType Leaf) {
    $props = Read-McProperties -Path $propsPath
    if ($props['rcon.port'] -match '^\d+$') { $rconPort = [int]$props['rcon.port'] }
}
elseif ($config['RCON_PORT'] -match '^\d+$') {
    $rconPort = [int]$config['RCON_PORT']
}

$allowRuleName = "Minecraft LAN Server (TCP $Port)"
$blockRconRuleName = "Minecraft LAN Server - Block RCON (TCP $rconPort)"
$isAdmin = Test-McAdmin

if ($Elevate -and -not $isAdmin) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-Run')
    if ($Remove) { $argList += '-Remove' }
    if ($Status) { $argList += '-Status' }
    $argList += @('-Port', [string]$Port)

    Write-McInfo '需要管理员权限，正在打开 UAC 授权窗口...'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait
        exit 0
    }
    catch {
        Write-McError "无法获取管理员权限：$($_.Exception.Message)"
        Write-McInfo '请右键 firewall.bat，选择“以管理员身份运行”。'
        exit 1
    }
}

if ($Status) {
    Write-McTitle "防火墙状态（TCP $Port）"
    try {
        $rule = @(Get-NetFirewallRule -DisplayName $allowRuleName -ErrorAction SilentlyContinue)
        if ($rule.Count -eq 0) {
            Write-McWarn "未找到放行规则：$allowRuleName"
        }
        else {
            Write-McOk "已找到放行规则：$allowRuleName（Enabled=$($rule[0].Enabled), Direction=$($rule[0].Direction), Action=$($rule[0].Action)）"
            $pf = $rule[0] | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            if ($pf) { Write-McInfo "规则协议：$($pf.Protocol)，本地端口：$($pf.LocalPort)" }
        }

        $blockRule = @(Get-NetFirewallRule -DisplayName $blockRconRuleName -ErrorAction SilentlyContinue)
        if ($blockRule.Count -gt 0) {
            Write-McInfo "RCON 入站阻断规则：已存在（$blockRconRuleName）"
        }
        else {
            Write-McWarn "RCON 入站阻断规则不存在。建议运行 firewall.bat 补全。"
        }

        Write-McInfo '当前防火墙配置文件：'
        Get-NetFirewallProfile -ErrorAction SilentlyContinue |
            Select-Object Name, Enabled |
            Format-Table -AutoSize
        Write-McInfo '当前网络连接：'
        Get-NetConnectionProfile -ErrorAction SilentlyContinue |
            Select-Object Name, InterfaceAlias, NetworkCategory |
            Format-Table -AutoSize
    }
    catch {
        Write-McError "读取防火墙状态失败：$($_.Exception.Message)"
        exit 1
    }
    if ($Run) { Read-Host '按回车关闭此窗口' | Out-Null }
    exit 0
}

if (-not $isAdmin) {
    Write-McError '需要管理员权限才能修改 Windows 防火墙。'
    Write-McInfo '请双击 firewall.bat（会自动弹出 UAC 授权），或右键以管理员身份运行。'
    exit 1
}

try {
    $service = Get-Service -Name MpsSvc -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        Write-McError "Windows 防火墙服务（MpsSvc）未运行：$($service.Status)"
        Write-McInfo '请先在“服务”中启动 Windows Defender Firewall，或检查第三方安全软件。'
        exit 1
    }
}
catch { }

if ($Remove) {
    Write-McTitle '移除 Minecraft 防火墙规则'
    foreach ($name in @($allowRuleName, $blockRconRuleName)) {
        $existing = @(Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
            Write-McOk "已移除：$name"
        }
        else {
            Write-McInfo "不存在，跳过：$name"
        }
    }
    if ($Run) { Read-Host '按回车关闭此窗口' | Out-Null }
    exit 0
}

Write-McTitle "配置 Windows 防火墙（TCP $Port）"
try {
    foreach ($name in @($allowRuleName, $blockRconRuleName)) {
        $existing = @(Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        }
    }

    New-NetFirewallRule `
        -DisplayName $allowRuleName `
        -Description 'Allow Minecraft Java Edition LAN clients to connect.' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -Profile Any `
        -Enabled True | Out-Null
    Write-McOk "已放行入站 TCP $Port（所有网络配置文件）。"

    if ($rconPort -ne $Port) {
        New-NetFirewallRule `
            -DisplayName $blockRconRuleName `
            -Description 'Block remote RCON access. Local stop.bat/admin.bat still works via 127.0.0.1.' `
            -Direction Inbound `
            -Action Block `
            -Protocol TCP `
            -LocalPort $rconPort `
            -Profile Any `
            -Enabled True | Out-Null
        Write-McOk "已阻止外部访问 RCON 端口 TCP $rconPort（本机 127.0.0.1 不受影响）。"
    }

    Write-McInfo '当前防火墙配置文件：'
    Get-NetFirewallProfile -ErrorAction SilentlyContinue |
        Select-Object Name, Enabled |
        Format-Table -AutoSize

    Write-McInfo '当前网络连接：'
    Get-NetConnectionProfile -ErrorAction SilentlyContinue |
        Select-Object Name, InterfaceAlias, NetworkCategory |
        Format-Table -AutoSize

    Write-McWarn '如果第三方杀毒软件（如 360、火绒）带有自己的防火墙，还需要在其中放行 TCP 25565。'
    Write-McInfo '如要撤销，请运行：firewall.bat -Remove（或在管理员 PowerShell 中运行本脚本 -Remove）。'
}
catch {
    Write-McError "配置防火墙失败：$($_.Exception.Message)"
    exit 1
}

if ($Run) { Read-Host '按回车关闭此窗口' | Out-Null }
exit 0
