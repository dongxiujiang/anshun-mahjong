param(
    [string]$GodotExe = "C:\Users\xiu\Desktop\Godot_v4.7.2-stable_win64.exe",
    [string]$Preset = "Android Internal QA",
    [string]$OutputApk = "C:\Users\xiu\Desktop\Mahjong-Godot\build\dongxiu-remake-25d.apk",
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$GameDir = Join-Path $RepoRoot "remake\game"
$BuildDir = Join-Path $RepoRoot "build"
$JavaHome = Join-Path $BuildDir "tools\java\jdk-17.0.16+8"
$AndroidHome = Join-Path $BuildDir "tools\android-sdk"
$AndroidUserHome = Join-Path $BuildDir "android-home"
$GradleTmp = Join-Path $BuildDir "gradle-tmp"
$StaleAssetsDir = Join-Path $GameDir "android\build\src\main\assets"
$StaleOutputsDir = Join-Path $GameDir "android\build\build\outputs\apk"

New-Item -ItemType Directory -Force -Path $AndroidUserHome, $GradleTmp, (Split-Path -Parent $OutputApk) | Out-Null

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidHome
$env:ANDROID_SDK_ROOT = $AndroidHome
$env:ANDROID_USER_HOME = $AndroidUserHome
$env:TEMP = $GradleTmp
$env:TMP = $GradleTmp
$env:GRADLE_OPTS = "-Djava.io.tmpdir=$GradleTmp"
$env:PATH = "$(Join-Path $JavaHome 'bin');$env:PATH"

if (-not (Test-Path $GodotExe)) {
    throw "Godot executable not found: $GodotExe"
}

$JavaBin = Join-Path $JavaHome "bin\java.exe"
if (-not (Test-Path $JavaBin)) {
    throw "JDK not found: $JavaBin"
}

Write-Host "[1/4] Checking Java runtime..." -ForegroundColor Cyan
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $JavaBin -version
$javaExit = $LASTEXITCODE
$ErrorActionPreference = $prevPref
if ($javaExit -ne 0) {
    throw "Java runtime failed to start (exit code $javaExit). If running inside a restricted sandbox, run this script directly in your local PowerShell terminal."
}

Write-Host "[2/4] Cleaning stale Android export cache..." -ForegroundColor Cyan
if (Test-Path $StaleAssetsDir) {
    Remove-Item -Recurse -Force $StaleAssetsDir
}
if (Test-Path $StaleOutputsDir) {
    Remove-Item -Recurse -Force $StaleOutputsDir
}
if (Test-Path $OutputApk) {
    Remove-Item -Force $OutputApk
}

Write-Host "[3/4] Exporting Android APK via Godot ($Preset)..." -ForegroundColor Cyan
$ExportFlag = if ($Release) { "--export-release" } else { "--export-debug" }
# Quote arguments explicitly for Windows PowerShell 5.1 Start-Process compatibility
$ExportArgs = @(
    "--headless",
    "--path", "`"$GameDir`"",
    $ExportFlag, "`"$Preset`"",
    "`"$OutputApk`""
)
$proc = Start-Process -FilePath $GodotExe -ArgumentList $ExportArgs -Wait -PassThru -NoNewWindow
$godotExit = $proc.ExitCode
if ($godotExit -ne 0 -or -not (Test-Path $OutputApk)) {
    throw "Godot Android export failed (exit code $godotExit)."
}

Write-Host "[4/4] Verifying APK signature and metadata..." -ForegroundColor Cyan
$Version = Get-Content (Join-Path $RepoRoot "remake\version.json") -Raw | ConvertFrom-Json
Write-Host "  Expected version: $($Version.version) (code $($Version.version_code))"
$BuildToolsDir = Get-ChildItem (Join-Path $AndroidHome "build-tools") -Directory | Sort-Object Name -Descending | Select-Object -First 1
if ($BuildToolsDir) {
    $ApkSigner = Join-Path $BuildToolsDir.FullName "apksigner.bat"
    if (Test-Path $ApkSigner) {
        $ErrorActionPreference = "Continue"
        & $ApkSigner verify --print-certs $OutputApk
        $signExit = $LASTEXITCODE
        $ErrorActionPreference = $prevPref
        if ($signExit -ne 0) {
            throw "APK signature verification failed (exit code $signExit)."
        }
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($OutputApk)
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $mustHave = @("TileResinSmooth", "MainLobbyBuilder", "LeaveConfirmOverlay", "TableTheme", "CareerPanel", "TingAssistantOverlay", "StatusTelemetryBar", "MahjongNames", "FlipChickenReveal", "table-layout.json", "tile_select")
    $mustNotHave = @("LayoutDesigner", "SeatedCharacter", "character_01_seated", "assets/tests/")
    foreach ($token in $mustHave) {
        if (-not ($names | Where-Object { $_ -like "*$token*" } | Select-Object -First 1)) {
            throw "APK verification failed: missing expected asset/script matching '$token'."
        }
    }
    foreach ($token in $mustNotHave) {
        if ($names | Where-Object { $_ -like "*$token*" } | Select-Object -First 1) {
            throw "APK verification failed: stale/excluded entry still present matching '$token'."
        }
    }
} finally {
    $zip.Dispose()
}

$Info = Get-Item $OutputApk
$Hash = (Get-FileHash $OutputApk -Algorithm SHA256).Hash
$SizeMB = [math]::Round($Info.Length / 1MB, 2)

Write-Host ""
Write-Host "APK build and verification succeeded!" -ForegroundColor Green
Write-Host "  Output : $($Info.FullName)"
Write-Host "  Size   : $SizeMB MB"
Write-Host "  SHA256 : $Hash"
