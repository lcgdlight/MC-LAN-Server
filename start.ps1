#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Root
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }
$OutputEncoding = New-Object System.Text.UTF8Encoding $false
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
try { $Host.UI.RawUI.WindowTitle = 'Minecraft 局域网服务器' } catch { }

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Java.ps1')

function Stop-McStart {
    param([string]$Message)
    Write-McError $Message
    exit 1
}

Write-McTitle 'Minecraft 局域网服务器（Fabric）一键启动'
Write-McInfo "服务端目录：$Root"

$envFile = Join-Path $Root 'server.env'
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    Stop-McStart "缺少配置文件 server.env。请确认文件完整，或重新解压本方案。"
}

$cfg = Read-McEnvFile -Path $envFile
$defaults = @{
    MC_VERSION          = '26.3'
    SERVER_JAR          = 'server.jar'
    SERVER_PORT         = '25565'
    ONLINE_MODE         = 'false'
    MOTD                = 'Fabric LAN Server | 26.3'
    MAX_PLAYERS         = '10'
    VIEW_DISTANCE       = '10'
    SIMULATION_DISTANCE = '10'
    SPAWN_PROTECTION    = '0'
    DIFFICULTY          = 'normal'
    GAMEMODE            = 'survival'
    PVP                 = 'true'
    WHITELIST           = 'false'
    MIN_MEMORY          = '2G'
    MAX_MEMORY          = '4G'
    JVM_ARGS            = ''
    JAVA_EXE            = ''
    RCON_PORT           = '25575'
}
foreach ($key in $defaults.Keys) {
    if (-not $cfg.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$cfg[$key])) {
        $cfg[$key] = $defaults[$key]
    }
}

try {
    $mcVersion = ([string]$cfg.MC_VERSION).Trim()
    if ($mcVersion -notmatch '^[0-9A-Za-z._-]+$') {
        throw "MC_VERSION 含有非法字符：$mcVersion"
    }
    $serverJarRel = ([string]$cfg.SERVER_JAR).Trim()
    $serverPort = Get-McInt -Value $cfg.SERVER_PORT -Default 25565 -Min 1 -Max 65535 -Name 'SERVER_PORT'
    $rconPort = Get-McInt -Value $cfg.RCON_PORT -Default 25575 -Min 1 -Max 65535 -Name 'RCON_PORT'
    if ($serverPort -eq $rconPort) {
        throw "SERVER_PORT 和 RCON_PORT 不能相同（当前都是 $serverPort）。"
    }
    $maxPlayers = Get-McInt -Value $cfg.MAX_PLAYERS -Default 10 -Min 1 -Max 1000 -Name 'MAX_PLAYERS'
    $viewDistance = Get-McInt -Value $cfg.VIEW_DISTANCE -Default 10 -Min 2 -Max 32 -Name 'VIEW_DISTANCE'
    $simulationDistance = Get-McInt -Value $cfg.SIMULATION_DISTANCE -Default 10 -Min 2 -Max 32 -Name 'SIMULATION_DISTANCE'
    $spawnProtection = Get-McInt -Value $cfg.SPAWN_PROTECTION -Default 0 -Min 0 -Max 1000 -Name 'SPAWN_PROTECTION'
    $onlineMode = ConvertTo-McBoolStrict -Value $cfg.ONLINE_MODE -Name 'ONLINE_MODE'
    $pvp = ConvertTo-McBoolStrict -Value $cfg.PVP -Name 'PVP'
    $whitelist = ConvertTo-McBoolStrict -Value $cfg.WHITELIST -Name 'WHITELIST'
    $difficulty = ([string]$cfg.DIFFICULTY).Trim().ToLowerInvariant()
    if ($difficulty -notmatch '^(peaceful|easy|normal|hard)$') {
        throw "DIFFICULTY 必须是 peaceful/easy/normal/hard，当前值：$difficulty"
    }
    $gameMode = ([string]$cfg.GAMEMODE).Trim().ToLowerInvariant()
    if ($gameMode -notmatch '^(survival|creative|adventure|spectator)$') {
        throw "GAMEMODE 必须是 survival/creative/adventure/spectator，当前值：$gameMode"
    }
    $motd = [string]$cfg.MOTD
    $minMemoryMB = ConvertTo-McMemoryMB -Value ([string]$cfg.MIN_MEMORY) -DefaultMB 2048 -Name 'MIN_MEMORY'
    $maxMemoryMB = ConvertTo-McMemoryMB -Value ([string]$cfg.MAX_MEMORY) -DefaultMB 4096 -Name 'MAX_MEMORY'
    if ($maxMemoryMB -lt $minMemoryMB) {
        throw "MAX_MEMORY（$maxMemoryMB MB）不能小于 MIN_MEMORY（$minMemoryMB MB）。"
    }

    $extraJvmArgs = @()
    $jvmArgsText = [string]$cfg.JVM_ARGS
    if (-not [string]::IsNullOrWhiteSpace($jvmArgsText)) {
        try {
            $extraJvmArgs = @(ConvertFrom-McWindowsCommandLine -CommandLine $jvmArgsText)
        }
        catch {
            throw "JVM_ARGS 格式错误：$($_.Exception.Message)。多个参数用空格分隔，含空格的参数值请用英文双引号包住。"
        }
        foreach ($arg in $extraJvmArgs) {
            if ([string]::IsNullOrWhiteSpace($arg) -or -not ($arg.StartsWith('-') -or $arg.StartsWith('@'))) {
                throw "JVM_ARGS 中的每一项都必须是 JVM 选项（通常以 - 开头），当前参数：$arg"
            }
            if ($arg -match '^(-cp|-classpath|--class-path|-jar)$') {
                throw "JVM_ARGS 不能包含 $arg；服务端主类和 classpath 由启动脚本管理。"
            }
        }
    }
}
catch {
    Stop-McStart $_.Exception.Message
}

try {
    $ramBytes = (Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Measure-Object -Property Capacity -Sum).Sum
    if ($ramBytes -and $ramBytes -gt 0) {
        $ramMB = [int]($ramBytes / 1MB)
        if ($maxMemoryMB -gt $ramMB) {
            Stop-McStart "MAX_MEMORY（$([math]::Round($maxMemoryMB / 1024, 1)) GB）超过物理内存（$([math]::Round($ramMB / 1024, 1)) GB）。请调低内存。"
        }
        if ($maxMemoryMB -gt [int]($ramMB * 0.8)) {
            Write-McWarn "MAX_MEMORY 已超过物理内存的 80%，可能导致系统卡顿。建议保留至少 2 GB 给 Windows。"
        }
    }
}
catch {
    if ($_.Exception.Message -like 'MAX_MEMORY*') { throw }
}

$jarPath = $serverJarRel
if (-not [System.IO.Path]::IsPathRooted($jarPath)) {
    $jarPath = Join-Path $Root $jarPath
}
$pidFile = Join-Path $Root 'run\server.pid'

$running = Get-McServerProcess -PidFile $pidFile -JarName $serverJarRel
if ($running) {
    Write-McTitle '服务器已经在运行'
    Write-McOk "Java 进程 PID：$($running.Id)"
    $addresses = @(Get-McLanAddresses)
    $primary = $addresses | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $primary -and $addresses.Count -gt 0) { $primary = $addresses[0] }
    if ($primary) {
        Write-Host ("  其他电脑填写：{0}:{1}" -f $primary.IPAddress, $serverPort) -ForegroundColor Yellow
    }
    Write-McInfo '如需停止，请双击 stop.bat（不要直接关闭服务器窗口）。'
    exit 0
}

if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

$serverPortOwners = @(Get-McPortInfo -Port $serverPort)
if ($serverPortOwners.Count -gt 0) {
    $desc = ($serverPortOwners | ForEach-Object { "$($_.ProcessName)（PID $($_.OwningProcess)）" }) -join '、'
    Stop-McStart "端口 $serverPort 已被占用：$desc。请关闭占用程序，或修改 server.env 中的 SERVER_PORT。"
}

$rconPortOwners = @(Get-McPortInfo -Port $rconPort)
if ($rconPortOwners.Count -gt 0) {
    $desc = ($rconPortOwners | ForEach-Object { "$($_.ProcessName)（PID $($_.OwningProcess)）" }) -join '、'
    Stop-McStart "RCON 端口 $rconPort 已被占用：$desc。请修改 server.env 中的 RCON_PORT。"
}

if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf)) {
    Write-McError "未找到服务端 jar：$jarPath"
    Write-McInfo '首次部署请确认 fabric-server-launch.jar 和 server.jar 已就位；不要用 download-server.bat 覆盖 Fabric 启动器。'
    Write-McInfo "如果手动下载，请确认文件名与 server.env 中的 SERVER_JAR 一致（当前：$serverJarRel）。"
    exit 1
}

$jarInfo = Get-McServerInfo -JarPath $jarPath -Root $Root
if ($jarInfo.McVersion -and $jarInfo.McVersion -ne $mcVersion) {
    Stop-McStart "服务端 jar 的版本是 Minecraft $($jarInfo.McVersion)，但 server.env 配置的是 $mcVersion。客户端将无法连接，请下载匹配版本或修改 MC_VERSION。"
}
$requiredJava = 25
if ($jarInfo.JavaVersion -and $jarInfo.JavaVersion -gt 0) {
    $requiredJava = [int]$jarInfo.JavaVersion
}

try {
    $javaSelection = Select-McJava -Root $Root -ConfiguredPath ([string]$cfg.JAVA_EXE) -RequiredMajor $requiredJava
}
catch {
    Stop-McStart $_.Exception.Message
}
$java = $javaSelection.Java
$javaDisplay = [string]$java.Version
if ($java.DetailedVersion) { $javaDisplay = "$($java.DetailedVersion)（Java $($java.Major)）" }
Write-McInfo "Java：$javaDisplay（$($java.Path)）"
if ($java.Major -gt $requiredJava) {
    Write-McWarn "服务端推荐 Java $requiredJava，当前使用更高版本 Java $($java.Major)。通常可以运行；若启动失败，请安装 Java $requiredJava。"
}
if ($java.Arch -and $java.Arch -ne '64') {
    Stop-McStart "检测到 $($java.Arch) 位 Java，Minecraft 服务端需要 64 位 Java。"
}

$eulaPath = Join-Path $Root 'eula.txt'
$eulaOk = $false
if (Test-Path -LiteralPath $eulaPath -PathType Leaf) {
    foreach ($line in [System.IO.File]::ReadAllLines($eulaPath, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^\s*eula\s*=\s*true\s*$') { $eulaOk = $true; break }
    }
}
if (-not $eulaOk) {
    $eulaText = "#By changing the setting below to TRUE you are indicating your agreement to the Minecraft EULA.`r`n#https://aka.ms/MinecraftEULA`r`neula=true`r`n"
    [System.IO.File]::WriteAllText($eulaPath, $eulaText, $Utf8NoBom)
    Write-McWarn '已自动写入 eula=true。继续启动即表示你同意 Minecraft 最终用户许可协议（EULA）。'
}
else {
    Write-McOk 'eula.txt 已确认（eula=true）。'
}

$propsPath = Join-Path $Root 'server.properties'
$props = Read-McProperties -Path $propsPath
$rconPassword = [string]$props['rcon.password']
if ($rconPassword -notmatch '^[A-Za-z0-9]{8,32}$') {
    $rconPassword = New-McPassword -Length 24
    Write-McInfo '已生成新的 RCON 管理密码（保存在 server.properties，stop.bat 会自动读取）。'
}

$propertyValues = [ordered]@{
    'server-port'             = [string]$serverPort
    'server-ip'               = ''
    'online-mode'             = $(if ($onlineMode) { 'true' } else { 'false' })
    'enforce-secure-profile'  = $(if ($onlineMode) { 'true' } else { 'false' })
    'motd'                    = (ConvertTo-McPropertiesValue -Value $motd)
    'max-players'             = [string]$maxPlayers
    'view-distance'           = [string]$viewDistance
    'simulation-distance'     = [string]$simulationDistance
    'spawn-protection'        = [string]$spawnProtection
    'difficulty'              = $difficulty
    'gamemode'                = $gameMode
    'pvp'                     = $(if ($pvp) { 'true' } else { 'false' })
    'white-list'              = $(if ($whitelist) { 'true' } else { 'false' })
    'enable-rcon'             = 'true'
    'rcon.port'               = [string]$rconPort
    'rcon.password'           = $rconPassword
    'broadcast-rcon-to-ops'   = 'true'
    'enable-status'           = 'true'
}
Update-McProperties -Path $propsPath -Values $propertyValues
Write-McOk 'server.properties 已更新（其他未托管配置和注释会保留）。'

# 单独保存一份 RCON 连接信息，避免服务器运行时 server.properties 被 Java 占用导致 stop/admin 读取失败。
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'run') | Out-Null
$rconInfoText = "SERVER_PORT=$serverPort`r`nRCON_PORT=$rconPort`r`nRCON_PASSWORD=$rconPassword`r`nUPDATED=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`r`n"
[System.IO.File]::WriteAllText((Join-Path $Root 'run\rcon.txt'), $rconInfoText, $Utf8NoBom)

$firewallRuleName = "Minecraft LAN Server (TCP $serverPort)"
try {
    $firewallRule = @(Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)
    if ($firewallRule.Count -eq 0) {
        Write-McWarn "未检测到防火墙放行规则。其他电脑可能无法连接；请双击 firewall.bat（会自动请求管理员权限）。"
    }
    elseif ([string]$firewallRule[0].Enabled -ne 'True') {
        Write-McWarn "防火墙规则“$firewallRuleName”存在但未启用。请双击 firewall.bat 重新配置。"
    }
    else {
        Write-McOk "Windows 防火墙规则已存在：$firewallRuleName"
    }
}
catch { }

try {
    $publicProfiles = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $_.NetworkCategory -eq 'Public' })
    if ($publicProfiles.Count -gt 0) {
        Write-McWarn '当前网络被 Windows 标记为“公用网络”。如果未运行 firewall.bat，入站连接会被拦截。'
    }
}
catch { }

$addresses = @(Get-McLanAddresses)
Write-McTitle '连接信息'
if ($addresses.Count -eq 0) {
    Write-McWarn '没有检测到局域网 IPv4 地址。请检查网线/Wi-Fi，或运行 ipconfig 查看。'
}
else {
    $primary = $addresses | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $primary) { $primary = $addresses[0] }
    Write-Host ("  本机局域网 IPv4 : {0}（{1}，/{2}）" -f $primary.IPAddress, $primary.InterfaceAlias, $primary.PrefixLength) -ForegroundColor Gray
    Write-Host ("  其他电脑填写    : {0}:{1}" -f $primary.IPAddress, $serverPort) -ForegroundColor Yellow
    if ($addresses.Count -gt 1) {
        Write-Host '  其他可用地址（请选择与朋友同一网段的）：' -ForegroundColor Gray
        foreach ($addr in $addresses) {
            if ($addr.IPAddress -eq $primary.IPAddress) { continue }
            Write-Host ("    {0}:{1}  ({2})" -f $addr.IPAddress, $serverPort, $addr.InterfaceAlias) -ForegroundColor DarkGray
        }
    }
}
Write-Host '  提示            : 朋友在 Minecraft「多人游戏 → 直接连接」中填上面的地址。' -ForegroundColor Gray

try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.Manufacturer -match 'VMware|VirtualBox|innotek' -or $cs.Model -match 'VMware') {
        Write-McWarn '检测到虚拟机环境：请把 VMware 网络模式设为“桥接（Bridged）”；NAT 模式下局域网其他电脑无法直接连接此虚拟机。'
    }
}
catch { }

$serverVersionText = $mcVersion
if ($jarInfo.McVersion) { $serverVersionText = [string]$jarInfo.McVersion }
$loaderText = [string]$jarInfo.Type
if ($jarInfo.Build) { $loaderText += ' build ' + $jarInfo.Build }
if ($jarInfo.ImplementationVersion) { $loaderText += '（' + $jarInfo.ImplementationVersion + '）' }

Write-McTitle '服务器信息'
Write-Host ("  服务端版本 : Minecraft {0}" -f $serverVersionText) -ForegroundColor Gray
Write-Host ("  加载器     : {0}" -f $loaderText) -ForegroundColor Gray
if ($jarInfo.Protocol) { Write-Host ("  协议版本   : {0}（客户端必须使用相同版本）" -f $jarInfo.Protocol) -ForegroundColor Gray }
Write-Host ("  服务端 jar : {0}" -f $jarPath) -ForegroundColor Gray
Write-Host ("  最大人数   : {0}" -f $maxPlayers) -ForegroundColor Gray
Write-Host ("  正版验证   : {0}" -f $(if ($onlineMode) { '开启（online-mode=true）' } else { '关闭（离线模式，朋友无需正版账号）' })) -ForegroundColor Gray
Write-Host ("  内存       : {0} MB - {1} MB" -f $minMemoryMB, $maxMemoryMB) -ForegroundColor Gray
if ($extraJvmArgs.Count -gt 0) {
    Write-Host ("  额外 JVM   : {0}" -f ($extraJvmArgs -join ' ')) -ForegroundColor Gray
}
Write-Host ("  视图距离   : {0}；模拟距离：{1}" -f $viewDistance, $simulationDistance) -ForegroundColor Gray
Write-Host ("  MOTD       : {0}" -f $motd) -ForegroundColor Gray
Write-Host '  停止服务器 : 双击 stop.bat（不要直接关闭服务器窗口）' -ForegroundColor Gray
Write-Host '  备份世界   : 双击 backup.bat（服务器运行中也能备份）' -ForegroundColor Gray

if (-not $onlineMode) {
    Write-McWarn '当前是离线模式：适合没有正版账号的朋友，但只应在可信局域网使用，不要直接暴露到公网。'
}

$aikarFlags = @(
    '-XX:+UseG1GC',
    '-XX:MaxGCPauseMillis=200',
    '-XX:+UnlockExperimentalVMOptions',
    '-XX:+DisableExplicitGC',
    '-XX:+AlwaysPreTouch',
    '-XX:G1NewSizePercent=30',
    '-XX:G1MaxNewSizePercent=40',
    '-XX:G1HeapRegionSize=8M',
    '-XX:G1ReservePercent=20',
    '-XX:G1HeapWastePercent=5',
    '-XX:G1MixedGCCountTarget=4',
    '-XX:G1MixedGCLiveThresholdPercent=90',
    '-XX:G1RSetUpdatingPauseTimePercent=5',
    '-XX:SurvivorRatio=32',
    '-XX:+PerfDisableSharedMem',
    '-XX:MaxTenuringThreshold=1',
    '-Dusing.aikars.flags=https://mcflags.emc.gs',
    '-Daikars.new.flags=true'
)
if ($java.Major -ge 27) {
    $aikarFlags += '-XX:G1IHOP=15'
}
else {
    $aikarFlags += '-XX:InitiatingHeapOccupancyPercent=15'
    $aikarFlags += '-XX:+ParallelRefProcEnabled'
}
$jvmArgs = @("-Xms$($minMemoryMB)M", "-Xmx$($maxMemoryMB)M") + $aikarFlags + $extraJvmArgs + @(
    '-Dfile.encoding=UTF-8',
    '-Dstdout.encoding=UTF-8',
    '-Dstderr.encoding=UTF-8'
)
$javaArgs = $jvmArgs + @('-jar', $serverJarRel, '--nogui')

Write-McTitle '启动服务器'
Write-McInfo '正在启动 Java 进程。首次启动需要生成世界，可能需要 1-3 分钟，请耐心等待。'
Write-McInfo '服务器运行期间请不要关闭此窗口；需要停止时双击 stop.bat。'

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'run') | Out-Null
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue

try {
    $argumentLine = ($javaArgs | ForEach-Object { ConvertTo-McWindowsArgument -Value ([string]$_) }) -join ' '
    $proc = Start-Process -FilePath $java.Path -ArgumentList $argumentLine -WorkingDirectory $Root -NoNewWindow -PassThru
}
catch {
    Stop-McStart "启动 Java 失败：$($_.Exception.Message)"
}

[System.IO.File]::WriteAllText($pidFile, [string]$proc.Id, $Utf8NoBom)
Write-McOk "服务器进程已启动，PID=$($proc.Id)。日志同时写入 logs\latest.log。"

$exitCode = 0
try {
    $proc.WaitForExit()
    $proc.Refresh()
    $exitCode = [int]$proc.ExitCode
}
finally {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

if ($exitCode -eq 0) {
    Write-McOk '服务器已正常退出（退出码 0）。世界和配置已经保存。'
}
else {
    Write-McWarn "服务器已退出，退出码：$exitCode。请查看上方日志或 logs\latest.log 排查原因。"
}
exit $exitCode

