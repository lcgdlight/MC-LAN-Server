# ============================================================
# MC-LAN-Server RCON 客户端（Source RCON 协议）
# 仅连接 127.0.0.1，用于安全停止服务器和执行管理命令。
# ============================================================

function Read-McExactBytes {
    param(
        [Parameter(Mandatory = $true)]$Stream,
        [Parameter(Mandatory = $true)][int]$Count
    )
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($read -le 0) { throw 'RCON 连接已关闭' }
        $offset += $read
    }
    return ,$buffer
}

function Send-McRconPacket {
    param(
        [Parameter(Mandatory = $true)]$Stream,
        [Parameter(Mandatory = $true)][int]$Id,
        [Parameter(Mandatory = $true)][int]$Type,
        [string]$Body = ''
    )
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $length = 4 + 4 + $bodyBytes.Length + 2
    $buffer = New-Object byte[] ($length + 4)
    [BitConverter]::GetBytes([int]$length).CopyTo($buffer, 0)
    [BitConverter]::GetBytes([int]$Id).CopyTo($buffer, 4)
    [BitConverter]::GetBytes([int]$Type).CopyTo($buffer, 8)
    if ($bodyBytes.Length -gt 0) {
        $bodyBytes.CopyTo($buffer, 12)
    }
    $Stream.Write($buffer, 0, $buffer.Length)
    $Stream.Flush()
}

function Read-McRconPacket {
    param([Parameter(Mandatory = $true)]$Stream)
    $lengthBytes = Read-McExactBytes -Stream $Stream -Count 4
    $length = [BitConverter]::ToInt32($lengthBytes, 0)
    if ($length -lt 10 -or $length -gt 1048576) {
        throw "RCON 数据包长度异常：$length"
    }
    $data = Read-McExactBytes -Stream $Stream -Count $length
    $id = [BitConverter]::ToInt32($data, 0)
    $type = [BitConverter]::ToInt32($data, 4)
    $bodyLength = $length - 10
    $body = ''
    if ($bodyLength -gt 0) {
        $body = [System.Text.Encoding]::UTF8.GetString($data, 8, $bodyLength)
    }
    return [pscustomobject]@{
        Id   = $id
        Type = $type
        Body = $body
    }
}

function Connect-McRcon {
    param(
        [string]$Server = '127.0.0.1',
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password,
        [int]$TimeoutMs = 5000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Server, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            throw "连接 RCON 超时（${Server}:$Port）"
        }
        $client.EndConnect($async)
        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $stream.WriteTimeout = $TimeoutMs

        Send-McRconPacket -Stream $stream -Id 1 -Type 3 -Body $Password
        $response = Read-McRconPacket -Stream $stream
        if ($response.Id -eq -1) {
            throw 'RCON 密码错误'
        }
        return [pscustomobject]@{
            Client = $client
            Stream = $stream
        }
    }
    catch {
        try { $client.Close() } catch { }
        throw
    }
}

function Invoke-McRconCommand {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command,
        [int]$TimeoutMs = 5000
    )
    $Session.Stream.ReadTimeout = $TimeoutMs
    Send-McRconPacket -Stream $Session.Stream -Id 2 -Type 2 -Body $Command

    $parts = New-Object 'System.Collections.Generic.List[string]'
    try {
        $response = Read-McRconPacket -Stream $Session.Stream
        [void]$parts.Add($response.Body)

        $deadline = [DateTime]::UtcNow.AddMilliseconds(250)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($Session.Stream.DataAvailable) {
                $response = Read-McRconPacket -Stream $Session.Stream
                [void]$parts.Add($response.Body)
                $deadline = [DateTime]::UtcNow.AddMilliseconds(150)
            }
            else {
                Start-Sleep -Milliseconds 30
            }
        }
    }
    catch [System.IO.IOException] {
        if ($parts.Count -eq 0) { throw }
    }
    return (($parts -join "`r`n").Trim())
}

function Close-McRcon {
    param($Session)
    if (-not $Session) { return }
    try { $Session.Stream.Close() } catch { }
    try { $Session.Client.Close() } catch { }
}

function Invoke-McRconStop {
    param([Parameter(Mandatory = $true)]$Session)
    try {
        [void](Invoke-McRconCommand -Session $Session -Command 'save-all flush' -TimeoutMs 15000)
    }
    catch { }
    Send-McRconPacket -Stream $Session.Stream -Id 2 -Type 2 -Body 'stop'
    Start-Sleep -Milliseconds 300
}
