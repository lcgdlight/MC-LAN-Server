# ============================================================
# MC-LAN-Server Java / 服务端 jar 检测
# ============================================================

function Add-McJavaCandidate {
    param(
        [Parameter(Mandatory = $true)]$List,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [System.IO.Path]::GetFullPath($Path) } catch { return }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
    foreach ($item in $List) {
        if ($item -ieq $full) { return }
    }
    [void]$List.Add($full)
}

function Get-McJavaCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ConfiguredPath
    )
    $list = New-Object 'System.Collections.Generic.List[string]'

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
            Add-McJavaCandidate -List $list -Path $ConfiguredPath
        }
        else {
            Add-McJavaCandidate -List $list -Path (Join-Path $Root $ConfiguredPath)
        }
        return @($list)
    }

    if ($env:JAVA_HOME) {
        Add-McJavaCandidate -List $list -Path (Join-Path $env:JAVA_HOME 'bin\java.exe')
    }

    $javaCmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($javaCmd) {
        Add-McJavaCandidate -List $list -Path $javaCmd.Source
    }

    $bases = New-Object 'System.Collections.Generic.List[string]'
    if ($env:ProgramFiles) {
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Java'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Eclipse Adoptium'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Microsoft'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Amazon Corretto'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Zulu'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'BellSoft'))
        [void]$bases.Add((Join-Path $env:ProgramFiles 'Semeru'))
    }
    if (${env:ProgramFiles(x86)}) {
        [void]$bases.Add((Join-Path ${env:ProgramFiles(x86)} 'Java'))
        [void]$bases.Add((Join-Path ${env:ProgramFiles(x86)} 'Eclipse Adoptium'))
    }
    if ($env:LOCALAPPDATA) {
        [void]$bases.Add((Join-Path $env:LOCALAPPDATA 'Programs\Eclipse Adoptium'))
        [void]$bases.Add((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft'))
    }
    if ($env:USERPROFILE) {
        [void]$bases.Add((Join-Path $env:USERPROFILE '.jdks'))
    }

    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        try {
            Get-ChildItem -LiteralPath $base -Directory -ErrorAction Stop | ForEach-Object {
                Add-McJavaCandidate -List $list -Path (Join-Path $_.FullName 'bin\java.exe')
            }
        }
        catch { }
    }

    $runtimeRoots = @()
    if ($env:APPDATA) { $runtimeRoots += (Join-Path $env:APPDATA '.minecraft\runtime') }
    if ($env:LOCALAPPDATA) {
        $runtimeRoots += (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.4297127D64EC6_8wekyb3d8bbwe\LocalCache\Local\runtime')
    }
    if (Test-Path -LiteralPath 'C:\.minecraft\runtime') { $runtimeRoots += 'C:\.minecraft\runtime' }

    foreach ($runtimeRoot in $runtimeRoots) {
        if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) { continue }
        try {
            Get-ChildItem -LiteralPath $runtimeRoot -Recurse -Filter 'java.exe' -File -Depth 4 -ErrorAction SilentlyContinue |
                ForEach-Object { Add-McJavaCandidate -List $list -Path $_.FullName }
        }
        catch { }
    }

    foreach ($pclRoot in @((Join-Path $env:APPDATA 'PCL'), (Join-Path $env:LOCALAPPDATA 'PCL'))) {
        if (-not $pclRoot -or -not (Test-Path -LiteralPath $pclRoot -PathType Container)) { continue }
        try {
            Get-ChildItem -LiteralPath $pclRoot -Recurse -Filter 'java.exe' -File -Depth 5 -ErrorAction SilentlyContinue |
                ForEach-Object { Add-McJavaCandidate -List $list -Path $_.FullName }
        }
        catch { }
    }

    return @($list)
}

function Get-McJavaInfo {
    param([Parameter(Mandatory = $true)][string]$JavaExe)
    if (-not (Test-Path -LiteralPath $JavaExe -PathType Leaf)) { return $null }

    $oldErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $JavaExe -XshowSettings:properties -version 2>&1 | Out-String
        if ([string]::IsNullOrWhiteSpace($output)) { return $null }

        $spec = $null
        $arch = $null
        $javaHome = $null
        $javaVersion = $null
        if ($output -match '(?m)^\s*java\.specification\.version\s*=\s*(\S+)') { $spec = $Matches[1] }
        if ($output -match '(?m)^\s*sun\.arch\.data\.model\s*=\s*(\S+)') { $arch = $Matches[1] }
        if ($output -match '(?m)^\s*java\.home\s*=\s*(.+)$') { $javaHome = $Matches[1].Trim() }
        if ($output -match '(?m)^\s*java\.version\s*=\s*(\S+)') { $javaVersion = $Matches[1] }
        if (-not $spec -and $output -match 'version "([^"]+)"') { $spec = $Matches[1] }
        if (-not $spec) { return $null }

        $major = 0
        if ($spec -like '1.*') {
            $parts = $spec.Split('.')
            if ($parts.Length -ge 2) { [void][int]::TryParse($parts[1], [ref]$major) }
        }
        else {
            $first = $spec.Split('.')[0]
            [void][int]::TryParse($first, [ref]$major)
        }
        if ($major -le 0) { return $null }

        return [pscustomobject]@{
            Path    = (Resolve-Path -LiteralPath $JavaExe).Path
            Major   = $major
            Version = $spec
            DetailedVersion = $javaVersion
            Arch    = $arch
            Home    = $javaHome
        }
    }
    catch {
        return $null
    }
    finally {
        $ErrorActionPreference = $oldErrorAction
    }
}

function Select-McJava {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ConfiguredPath,
        [Parameter(Mandatory = $true)][int]$RequiredMajor
    )
    $paths = Get-McJavaCandidates -Root $Root -ConfiguredPath $ConfiguredPath
    $infos = @()
    foreach ($path in $paths) {
        $info = Get-McJavaInfo -JavaExe $path
        if ($info) { $infos += $info }
    }

    if ($infos.Count -eq 0) {
        throw "未检测到可用的 Java。请安装 Java $RequiredMajor（64 位）后重试，或在 server.env 的 JAVA_EXE 中填写 java.exe 的完整路径。"
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $chosen = $infos[0]
        if ($chosen.Major -lt $RequiredMajor) {
            throw "JAVA_EXE 指定的 Java 版本过低：$($chosen.Version)，服务端需要 Java $RequiredMajor 或更高版本。"
        }
        if ($chosen.Arch -eq '32') {
            throw "JAVA_EXE 指定的是 32 位 Java，Minecraft 服务端需要 64 位 Java。"
        }
        return [pscustomobject]@{ Java = $chosen; All = $infos; IsConfigured = $true }
    }

    $eligible = @($infos | Where-Object { $_.Major -ge $RequiredMajor -and $_.Arch -ne '32' })
    if ($eligible.Count -eq 0) {
        $desc = ($infos | ForEach-Object { "Java $($_.Major)（$($_.Path)）" }) -join '；'
        throw "未找到 Java $RequiredMajor 或更高版本（64 位）。已检测到：$desc"
    }

    $chosen = $eligible |
        Sort-Object @{ Expression = { if ($_.Major -eq $RequiredMajor) { 0 } else { 1 } } }, Major |
        Select-Object -First 1

    return [pscustomobject]@{ Java = $chosen; All = $infos; IsConfigured = $false }
}

function Read-McZipText {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)][string]$EntryName
    )
    $entry = $Zip.GetEntry($EntryName)
    if (-not $entry) { return $null }
    $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function ConvertFrom-McManifest {
    param([string]$Text)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }
    $current = $null
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.StartsWith(' ')) {
            if ($current) { $result[$current] = [string]$result[$current] + $line.Substring(1) }
            continue
        }
        if ($line -match '^([^:]+):\s*(.*)$') {
            $current = $Matches[1].Trim()
            $result[$current] = $Matches[2].Trim()
        }
    }
    return $result
}

function Get-McJarBasicInfo {
    param([Parameter(Mandatory = $true)][string]$JarPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $info = [pscustomobject]@{
        Type                  = 'Unknown'
        McVersion             = $null
        Protocol              = $null
        JavaVersion           = $null
        Build                 = $null
        ImplementationVersion = $null
        MainClass             = $null
    }

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($JarPath)

        $versionText = Read-McZipText -Zip $zip -EntryName 'version.json'
        if ($versionText) {
            try {
                $versionJson = $versionText | ConvertFrom-Json
                if ($versionJson.id) { $info.McVersion = [string]$versionJson.id }
                if ($versionJson.protocol_version) { $info.Protocol = [int]$versionJson.protocol_version }
                if ($versionJson.java_version) { $info.JavaVersion = [int]$versionJson.java_version }
            }
            catch { }
        }

        $manifestText = Read-McZipText -Zip $zip -EntryName 'META-INF/MANIFEST.MF'
        if ($manifestText) {
            $manifest = ConvertFrom-McManifest -Text $manifestText
            if ($manifest['Main-Class']) { $info.MainClass = [string]$manifest['Main-Class'] }
            if ($manifest['Implementation-Version']) { $info.ImplementationVersion = [string]$manifest['Implementation-Version'] }
            if ($manifest['Build-Number']) { $info.Build = [string]$manifest['Build-Number'] }
        }
    }
    finally {
        if ($zip) { $zip.Dispose() }
    }

    $main = [string]$info.MainClass
    if ($main -match 'paperclip|papermc|paper') { $info.Type = 'Paper' }
    elseif ($main -match 'fabric') { $info.Type = 'Fabric' }
    elseif ($main -match 'neoforge') { $info.Type = 'NeoForge' }
    elseif ($main -match 'forge|bootstraplauncher') { $info.Type = 'Forge' }
    elseif ($main -match 'minecraft') { $info.Type = 'Vanilla' }
    else { $info.Type = 'Vanilla' }

    if ($info.Type -eq 'Paper' -and $info.McVersion) {
        $jarDir = Split-Path -Parent $JarPath
        $patched = Join-Path $jarDir ("versions\$($info.McVersion)\paper-$($info.McVersion).jar")
        if (Test-Path -LiteralPath $patched -PathType Leaf) {
            $patchedZip = $null
            try {
                $patchedZip = [System.IO.Compression.ZipFile]::OpenRead($patched)
                $patchedManifest = Read-McZipText -Zip $patchedZip -EntryName 'META-INF/MANIFEST.MF'
                if ($patchedManifest) {
                    $pm = ConvertFrom-McManifest -Text $patchedManifest
                    if ($pm['Implementation-Version']) { $info.ImplementationVersion = [string]$pm['Implementation-Version'] }
                    if ($pm['Build-Number']) { $info.Build = [string]$pm['Build-Number'] }
                }
            }
            catch { }
            finally {
                if ($patchedZip) { $patchedZip.Dispose() }
            }
        }
    }

    return $info
}

function Get-McServerInfo {
    param(
        [Parameter(Mandatory = $true)][string]$JarPath,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $info = Get-McJarBasicInfo -JarPath $JarPath

    $metaPath = Join-Path $Root 'server-info.txt'
    if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
        $meta = Read-McServerInfoFile -Path $metaPath
        $matchesSize = $true
        if ($meta['SIZE']) {
            try {
                $matchesSize = ((Get-Item -LiteralPath $JarPath).Length -eq [long]$meta['SIZE'])
            }
            catch { $matchesSize = $false }
        }
        if ($matchesSize) {
            if ($meta['TYPE']) { $info.Type = $meta['TYPE'] }
            if ($meta['MC_VERSION']) { $info.McVersion = $meta['MC_VERSION'] }
            if ($meta['PROTOCOL']) { $info.Protocol = [int]$meta['PROTOCOL'] }
            if ($meta['BUILD']) { $info.Build = $meta['BUILD'] }
            if ($meta['IMPLEMENTATION_VERSION']) { $info.ImplementationVersion = $meta['IMPLEMENTATION_VERSION'] }
        }
    }

    return $info
}
