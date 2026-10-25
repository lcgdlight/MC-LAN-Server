#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$McDir = 'C:\.minecraft'
$VersionId = 'fabric-loader-0.20.1-26.3'
$VersionDir = Join-Path $McDir "versions\$VersionId"
$VersionJson = Join-Path $VersionDir "$VersionId.json"

if (-not (Test-Path -LiteralPath $VersionJson -PathType Leaf)) {
    Write-Host "[ERROR] Fabric client version not found: $VersionJson" -ForegroundColor Red
    Write-Host 'Install Fabric 26.3 (loader 0.20.1) with the Fabric installer or PCL first.' -ForegroundColor Yellow
    exit 1
}

$Version = Get-Content -LiteralPath $VersionJson -Raw | ConvertFrom-Json
$ParentId = [string]$Version.inheritsFrom
if ([string]::IsNullOrWhiteSpace($ParentId)) { $ParentId = '26.3' }
$ParentJson = Join-Path $McDir "versions\$ParentId\$ParentId.json"
$Parent = Get-Content -LiteralPath $ParentJson -Raw | ConvertFrom-Json

$libMap = [ordered]@{}
foreach ($lib in @($Parent.libraries) + @($Version.libraries)) {
    if (-not $lib.name) { continue }
    $rel = $null
    if ($lib.downloads -and $lib.downloads.artifact -and $lib.downloads.artifact.path) {
        $rel = [string]$lib.downloads.artifact.path
    }
    else {
        $parts = ([string]$lib.name) -split ':'
        if ($parts.Count -ge 3) {
            $group = $parts[0]
            $artifact = $parts[1]
            $ver = $parts[2]
            $classifier = ''
            if ($parts.Count -ge 4 -and $parts[3]) { $classifier = '-' + $parts[3] }
            $file = "$artifact-$ver$classifier.jar"
            $rel = (($group -replace '\.', '/') + "/$artifact/$ver/$file")
        }
    }
    if ($rel) { $libMap[[string]$lib.name] = (Join-Path $McDir "libraries\$rel") }
}

$clientJar = Join-Path $McDir "versions\$ParentId\$ParentId.jar"
$classpathItems = New-Object System.Collections.Generic.List[string]
foreach ($p in $libMap.Values) {
    if (Test-Path -LiteralPath $p -PathType Leaf) { $classpathItems.Add($p) }
    else { Write-Host "[WARN] missing library: $p" -ForegroundColor Yellow }
}
if (Test-Path -LiteralPath $clientJar -PathType Leaf) { $classpathItems.Add($clientJar) }
else {
    Write-Host "[ERROR] missing client jar: $clientJar" -ForegroundColor Red
    exit 1
}
$classpath = ($classpathItems -join ';')

$natives = Join-Path $McDir "versions\$ParentId\$ParentId-natives"
$modsDir = Join-Path $VersionDir 'mods'
New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

$env:GALLIUM_DRIVER = 'llvmpipe'
$env:MESA_GL_VERSION_OVERRIDE = '4.6'
$env:MESA_GLSL_VERSION_OVERRIDE = '460'
$env:MESA_DEBUG = '0'
$env:PATH = 'C:\mesa\x64;' + $env:PATH

$java = 'C:\Program Files\Java\jdk-27.0.1.0.3\bin\java.exe'
if (-not (Test-Path -LiteralPath $java -PathType Leaf)) {
    $cmd = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($cmd) { $java = $cmd.Source }
    else {
        Write-Host '[ERROR] Java not found. Install Java 25+ or edit this script.' -ForegroundColor Red
        exit 1
    }
}

$assetIndex = '34'
if ($Parent.assetIndex -and $Parent.assetIndex.id) { $assetIndex = [string]$Parent.assetIndex.id }

$jvmArgs = @(
    '-Dorg.lwjgl.opengl.libname=C:\mesa\x64\opengl32.dll',
    '-XX:HeapDumpPath=MojangTricksIntelDriversForPerformance_javaw.exe_minecraft.exe.heapdump',
    '-XX:StackShadowPages=32',
    '--sun-misc-unsafe-memory-access=allow',
    '--enable-native-access=ALL-UNNAMED',
    '--add-exports', 'java.base/jdk.internal.misc=ALL-UNNAMED',
    "-Djava.library.path=$natives\java",
    "-Djna.tmpdir=$natives\jna",
    "-Dorg.lwjgl.system.SharedLibraryExtractPath=$natives\lwjgl",
    "-Dio.netty.native.workdir=$natives\netty",
    '-Dminecraft.launcher.brand=PCL',
    '-Dminecraft.launcher.version=408',
    '-Dlog4j2.formatMsgNoLookups=true',
    '-Dstdout.encoding=utf-8',
    '-Dstderr.encoding=utf-8',
    '-javaagent:C:\PCL\LwjglUnsafeAgent.jar',
    '-Xmx4G',
    '-XX:+UseG1GC',
    '-XX:MaxGCPauseMillis=50',
    '-DFabricMcEmu=net.minecraft.client.main.Main',
    '-cp', $classpath,
    [string]$Version.mainClass
)

$gameArgs = @(
    '--username', 'xxxx',
    '--version', $VersionId,
    '--gameDir', $VersionDir,
    '--assetsDir', (Join-Path $McDir 'assets'),
    '--assetIndex', $assetIndex,
    '--uuid', '0000000000003004998F501A96E8162A',
    '--accessToken', '0000000000003004998F501A96E8162A',
    '--clientId', '${clientid}',
    '--xuid', '${auth_xuid}',
    '--versionType', 'PCL',
    '--width', '854',
    '--height', '480',
    '--quickPlayMultiplayer', '192.168.1.12:25565'
)

Write-Host "Minecraft 26.3 / Fabric Loader 0.20.1" -ForegroundColor Cyan
Write-Host "Game directory: $VersionDir" -ForegroundColor DarkGray
Write-Host "Client mods:   $modsDir" -ForegroundColor DarkGray
Write-Host 'Starting with Mesa llvmpipe...' -ForegroundColor Green
Write-Host ''

Push-Location -LiteralPath $VersionDir
try {
    & $java @jvmArgs @gameArgs
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host "Game exited with code $exitCode." -ForegroundColor Yellow
exit $exitCode
