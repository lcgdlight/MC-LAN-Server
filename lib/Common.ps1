# ============================================================
# MC-LAN-Server 公共函数库（基础部分）
# 被 start.ps1 / stop.ps1 / admin.ps1 / firewall.ps1 引用
# 请不要单独双击本文件。
# ============================================================

function Write-McTitle {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
}

function Write-McInfo {
    param([string]$Text)
    Write-Host ('[信息] ' + $Text) -ForegroundColor Cyan
}

function Write-McOk {
    param([string]$Text)
    Write-Host ('[完成] ' + $Text) -ForegroundColor Green
}

function Write-McWarn {
    param([string]$Text)
    Write-Host ('[警告] ' + $Text) -ForegroundColor Yellow
}

function Write-McError {
    param([string]$Text)
    Write-Host ('[错误] ' + $Text) -ForegroundColor Red
}

function Read-McTextFileShared {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Retries = 6,
        [int]$DelayMs = 120
    )
    for ($i = 0; $i -lt $Retries; $i++) {
        $stream = $null
        $reader = $null
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            return $reader.ReadToEnd()
        }
        catch [System.IO.IOException] {
            if ($i -eq ($Retries - 1)) { throw }
            Start-Sleep -Milliseconds $DelayMs
        }
        finally {
            if ($reader) { $reader.Dispose() }
            elseif ($stream) { $stream.Dispose() }
        }
    }
}

function Read-McEnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $cfg = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $cfg }
    $text = Read-McTextFileShared -Path $Path
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $idx = $t.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $t.Substring(0, $idx).Trim().ToUpperInvariant()
        $value = $t.Substring($idx + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value.Substring(0, 1)
            $last = $value.Substring($value.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        $cfg[$key] = $value
    }
    return $cfg
}

function Read-McProperties {
    param([Parameter(Mandatory = $true)][string]$Path)
    $props = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $props }
    $text = Read-McTextFileShared -Path $Path
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#') -or $t.StartsWith('!')) { continue }
        $idx = $t.IndexOf('=')
        if ($idx -lt 1) { $idx = $t.IndexOf(':') }
        if ($idx -lt 1) { continue }
        $key = $t.Substring(0, $idx).Trim()
        $val = $t.Substring($idx + 1).Trim()
        $props[$key] = $val
    }
    return $props
}

function ConvertTo-McBoolStrict {
    param([object]$Value, [string]$Name)
    $s = ([string]$Value).Trim().ToLowerInvariant()
    switch ($s) {
        'true' { return $true }
        'yes' { return $true }
        'on' { return $true }
        '1' { return $true }
        'false' { return $false }
        'no' { return $false }
        'off' { return $false }
        '0' { return $false }
    }
    throw "$Name 必须是 true 或 false，当前值：$Value"
}

function Get-McInt {
    param([object]$Value, [int]$Default, [int]$Min, [int]$Max, [string]$Name)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    $n = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n)) {
        throw "$Name 必须是整数，当前值：$Value"
    }
    if ($n -lt $Min -or $n -gt $Max) {
        throw "$Name 必须在 $Min 到 $Max 之间，当前值：$n"
    }
    return $n
}

function ConvertTo-McMemoryMB {
    param([string]$Value, [int]$DefaultMB = 4096, [string]$Name = '内存')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $DefaultMB }
    $s = $Value.Trim().ToUpperInvariant()
    if ($s -match '^(\d+)\s*([GM])$') {
        $n = [int]$Matches[1]
        if ($Matches[2] -eq 'G') { return $n * 1024 }
        return $n
    }
    if ($s -match '^\d+$') { return [int]$s }
    throw "$Name 格式错误：$Value（示例：2G、4096M）"
}

function New-McPassword {
    param([int]$Length = 24)
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        [void]$sb.Append($chars[(Get-Random -Minimum 0 -Maximum $chars.Length)])
    }
    return $sb.ToString()
}

function ConvertTo-McPropertiesValue {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $sb = New-Object System.Text.StringBuilder
    $index = 0
    foreach ($ch in $Value.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq "`r") { $index++; continue }
        if ($ch -eq "`n") {
            [void]$sb.Append('\n')
        }
        elseif ($code -lt 32 -or $code -gt 126) {
            [void]$sb.Append('\u' + $code.ToString('X4'))
        }
        elseif ($ch -eq '\') {
            [void]$sb.Append('\\')
        }
        elseif ($ch -eq '=' -or $ch -eq ':') {
            [void]$sb.Append('\' + $ch)
        }
        elseif ($index -eq 0 -and $ch -eq ' ') {
            [void]$sb.Append('\ ')
        }
        else {
            [void]$sb.Append($ch)
        }
        $index++
    }
    return $sb.ToString()
}

function Update-McProperties {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Values
    )
    $lines = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $text = Read-McTextFileShared -Path $Path
        $lines = @($text -split "`r?`n")
    }
    else {
        $lines = @(
            '#Minecraft server properties',
            '#Managed by MC-LAN-Server. Managed keys are refreshed on every start.',
            '#Settings live in server.env; unknown keys and comments here are preserved.'
        )
    }

    $seen = @{}
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim.Length -eq 0 -or $trim.StartsWith('#') -or $trim.StartsWith('!')) {
            [void]$out.Add($line)
            continue
        }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) {
            [void]$out.Add($line)
            continue
        }
        $key = $line.Substring(0, $idx).Trim()
        if ($Values.Contains($key)) {
            if (-not $seen.ContainsKey($key)) {
                [void]$out.Add($key + '=' + $Values[$key])
                $seen[$key] = $true
            }
            continue
        }
        [void]$out.Add($line)
    }
    foreach ($key in $Values.Keys) {
        if (-not $seen.ContainsKey($key)) {
            [void]$out.Add($key + '=' + $Values[$key])
        }
    }

    $text = ($out -join "`r`n") + "`r`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $text, $utf8NoBom)
}

function Get-McPortInfo {
    param([Parameter(Mandatory = $true)][int]$Port)
    $found = @()
    $seenPids = @{}
    try {
        $conns = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
        foreach ($c in @($conns)) {
            if ($seenPids.ContainsKey([int]$c.OwningProcess)) { continue }
            $seenPids[[int]$c.OwningProcess] = $true
            $procName = '未知进程'
            try {
                $p = Get-Process -Id $c.OwningProcess -ErrorAction Stop
                $procName = $p.ProcessName
            }
            catch { }
            $found += [pscustomobject]@{
                Port          = $Port
                LocalAddress  = $c.LocalAddress
                OwningProcess = [int]$c.OwningProcess
                ProcessName   = $procName
            }
        }
    }
    catch {
        $lines = & netstat.exe -ano -p tcp 2>$null
        foreach ($line in $lines) {
            if ($line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$') {
                if ([int]$Matches[1] -ne $Port) { continue }
                $procId = [int]$Matches[2]
                if ($seenPids.ContainsKey($procId)) { continue }
                $seenPids[$procId] = $true
                $procName = '未知进程'
                try {
                    $p = Get-Process -Id $procId -ErrorAction Stop
                    $procName = $p.ProcessName
                }
                catch { }
                $found += [pscustomobject]@{
                    Port          = $Port
                    LocalAddress  = '*'
                    OwningProcess = $procId
                    ProcessName   = $procName
                }
            }
        }
    }
    return @($found)
}

function Get-McLanAddresses {
    $result = New-Object 'System.Collections.Generic.List[object]'
    $defaultIfIndex = $null
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object { $_.RouteMetric + $_.InterfaceMetric } |
            Select-Object -First 1
        if ($route) { $defaultIfIndex = $route.InterfaceIndex }
    }
    catch { }

    $seen = @{}
    try {
        $cfgs = Get-NetIPConfiguration -ErrorAction Stop
        foreach ($c in @($cfgs)) {
            if (-not $c.NetAdapter -or $c.NetAdapter.Status -ne 'Up') { continue }
            foreach ($a in @($c.IPv4Address)) {
                if (-not $a) { continue }
                $ip = [string]$a.IPAddress
                if ($ip -match '^127\.' -or $ip -match '^169\.254\.') { continue }
                if ($seen.ContainsKey($ip)) { continue }
                $seen[$ip] = $true
                $result.Add([pscustomobject]@{
                    IPAddress      = $ip
                    PrefixLength   = $a.PrefixLength
                    InterfaceAlias = $c.InterfaceAlias
                    IsDefault      = ($c.InterfaceIndex -eq $defaultIfIndex)
                })
            }
        }
    }
    catch {
        try {
            foreach ($ip in [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())) {
                if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                $text = $ip.IPAddressToString
                if ($text -match '^127\.' -or $text -match '^169\.254\.') { continue }
                if ($seen.ContainsKey($text)) { continue }
                $seen[$text] = $true
                $result.Add([pscustomobject]@{
                    IPAddress      = $text
                    PrefixLength   = 24
                    InterfaceAlias = '未知网卡'
                    IsDefault      = ($result.Count -eq 0)
                })
            }
        }
        catch { }
    }

    return @($result | Sort-Object @{ Expression = { $_.IsDefault }; Descending = $true }, IPAddress)
}

function Get-McServerProcess {
    param(
        [Parameter(Mandatory = $true)][string]$PidFile,
        [Parameter(Mandatory = $true)][string]$JarName
    )
    if (-not (Test-Path -LiteralPath $PidFile -PathType Leaf)) { return $null }
    $raw = ''
    try { $raw = [System.IO.File]::ReadAllText($PidFile).Trim() } catch { return $null }
    if ($raw -notmatch '^\d+$') { return $null }
    $procId = [int]$raw
    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $proc) { return $null }
    if ($proc.ProcessName -notmatch '^java') { return $null }

    $cmd = $null
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction Stop
        $cmd = $cim.CommandLine
    }
    catch { }

    $leaf = Split-Path -Leaf $JarName
    if ($cmd -and $leaf -and ($cmd -notmatch [regex]::Escape($leaf))) {
        return $null
    }
    return [pscustomobject]@{
        Id          = $procId
        Process     = $proc
        CommandLine = $cmd
    }
}

function Read-McServerInfoFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $info = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $info }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $idx = $t.IndexOf('=')
        if ($idx -lt 1) { continue }
        $key = $t.Substring(0, $idx).Trim().ToUpperInvariant()
        $info[$key] = $t.Substring($idx + 1).Trim()
    }
    return $info
}

function ConvertFrom-McWindowsCommandLine {
    param([AllowEmptyString()][string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return @() }
    if ($CommandLine -match "[`r`n`0]") {
        throw '参数中不能包含换行符或空字符'
    }

    $result = New-Object 'System.Collections.Generic.List[string]'
    $sb = New-Object System.Text.StringBuilder
    $inQuotes = $false
    $argStarted = $false
    $i = 0
    while ($i -lt $CommandLine.Length) {
        $ch = $CommandLine[$i]

        if ($ch -eq '\') {
            $slashCount = 0
            while ($i -lt $CommandLine.Length -and $CommandLine[$i] -eq '\') {
                $slashCount++
                $i++
            }
            if ($i -lt $CommandLine.Length -and $CommandLine[$i] -eq '"') {
                if ($slashCount -ge 2) {
                    [void]$sb.Append(('\' * [int][math]::Floor($slashCount / 2)))
                }
                if (($slashCount % 2) -eq 1) {
                    [void]$sb.Append('"')
                    $i++
                }
            }
            else {
                if ($slashCount -gt 0) { [void]$sb.Append(('\' * $slashCount)) }
            }
            $argStarted = $true
            continue
        }

        if ($ch -eq '"') {
            $inQuotes = -not $inQuotes
            $argStarted = $true
            $i++
            continue
        }

        if (($ch -eq ' ' -or $ch -eq "`t") -and -not $inQuotes) {
            if ($argStarted) {
                $result.Add($sb.ToString())
                [void]$sb.Clear()
                $argStarted = $false
            }
            $i++
            continue
        }

        [void]$sb.Append($ch)
        $argStarted = $true
        $i++
    }

    if ($inQuotes) { throw '参数中的双引号没有闭合' }
    if ($argStarted) { $result.Add($sb.ToString()) }
    return @($result)
}

function ConvertTo-McWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
            continue
        }
        if ($ch -eq '"') {
            if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2 + 1))) }
            else { [void]$sb.Append('\') }
            [void]$sb.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            [void]$sb.Append(('\' * $slashes))
            $slashes = 0
        }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2))) }
    [void]$sb.Append('"')
    return $sb.ToString()
}
