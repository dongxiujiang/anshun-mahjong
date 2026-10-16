[CmdletBinding()]
param(
    [ValidateSet("Check", "Full", "Patch")]
    [string]$Mode = "Check",
    [string]$GodotPath = "",
    [string]$PatchVersion = "",
    [string]$BaselinePath = "",
    [string]$Notes = "",
    [switch]$SkipNetwork,
    [switch]$SkipCoreTests,
    [switch]$PauseOnError
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location -LiteralPath $projectRoot

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogDirectory = Join-Path $projectRoot "build\local-build-release\$stamp"
New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null

function Write-Stage([string]$Message) {
    Write-Host "`n==== $Message ====" -ForegroundColor Cyan
}

function Resolve-File([string]$Value, [string[]]$Candidates, [string]$Label) {
    if ($Value -ne "") {
        if (Test-Path -LiteralPath $Value -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Value).Path
        }
        $explicitCommand = Get-Command $Value -ErrorAction SilentlyContinue
        if ($null -ne $explicitCommand -and $explicitCommand.CommandType -eq "Application") {
            return $explicitCommand.Source
        }
        throw "指定的 $Label 路径不存在或不可执行：$Value"
    }
    $paths = $Candidates
    foreach ($candidate in $paths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command -and $command.CommandType -eq "Application") {
            return $command.Source
        }
    }
    throw "未找到 $Label。请通过参数指定路径，或先安装对应工具。"
}

function Invoke-LoggedStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
    $logPath = Join-Path $script:LogDirectory "$safeName.log"
    Write-Host "[RUN] $Name" -ForegroundColor Yellow
    Write-Host "      日志：$logPath" -ForegroundColor DarkGray
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 会把原生命令的 stderr 包装成 ErrorRecord；收集后统一写日志，避免误判或刷屏。
        $ErrorActionPreference = "Continue"
        $captured = @(& $FilePath @Arguments 2>&1)
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $outputLines = foreach ($item in $captured) {
            if ($item -is [System.Management.Automation.ErrorRecord]) {
                $message = [string]$item.Exception.Message
                if ($message -ne "") { $message }
            }
            else {
                [string]$item
            }
        }
        $output = $outputLines -join [Environment]::NewLine
        $header = "# Step: $Name`r`n# Exit code: $exitCode`r`n"
        if ($output -ne "") { $header += "`r`n" }
        [IO.File]::WriteAllText($logPath, $header + $output, [Text.UTF8Encoding]::new($false))
        if ($output -ne "") { Write-Host $output.TrimEnd() }
    }
    catch {
        throw "[$Name] 启动失败：$($_.Exception.Message)。日志：$logPath"
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "[$Name] 退出码为 $exitCode。请查看日志：$logPath"
    }
    Write-Host "[ OK ] $Name" -ForegroundColor Green
}

function Invoke-PythonStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    Invoke-LoggedStep -Name $Name -FilePath $script:PythonExecutable -Arguments ($script:PythonPrefix + $Arguments)
}

function Get-ProjectSetting([string]$Key, [string]$Default = "") {
    $quote = [char]34
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=' + $quote + '([^' + $quote + '\r\n]*)' + $quote
    $match = [regex]::Match($script:ProjectText, $pattern)
    if ($match.Success) { return $match.Groups[1].Value }
    if ($Default -ne "") { return $Default }
    throw "project.godot 缺少设置：$Key"
}

function Check-GodotEditorClosed {
    $normalized = $projectRoot.Replace("\", "/").ToLowerInvariant()
    $running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match "^Godot.*\.exe$" -and
            $_.CommandLine -and
            $_.CommandLine.ToLowerInvariant().Contains($normalized) -and
            $_.CommandLine.ToLowerInvariant().Contains("--editor")
        }
    if ($null -ne $running) {
        throw "检测到 Godot 编辑器正在打开当前工程。请先保存并关闭编辑器，再运行本地发布检查；如必须保留编辑器，请使用单独的工程副本。"
    }
}

function Check-AndroidEnvironment {
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if ([string]::IsNullOrWhiteSpace($sdk) -or -not (Test-Path -LiteralPath $sdk -PathType Container)) {
        throw "未找到 Android SDK。请设置 ANDROID_HOME 或 ANDROID_SDK_ROOT。"
    }
    if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME) -or -not (Test-Path -LiteralPath $env:JAVA_HOME -PathType Container)) {
        throw "未找到 Java SDK。请设置 JAVA_HOME。"
    }
    $signing = Join-Path $projectRoot ".godot\export_credentials.cfg"
    if (-not (Test-Path -LiteralPath $signing -PathType Leaf)) {
        throw "缺少 .godot/export_credentials.cfg，无法在本地验证正式签名 APK。请先配置本地正式签名凭据。"
    }
    $apksigner = Get-ChildItem -LiteralPath (Join-Path $sdk "build-tools") -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("apksigner.exe", "apksigner.bat") } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($null -eq $apksigner) {
        throw "Android SDK 中未找到 apksigner，请安装对应的 build-tools。"
    }
    return $apksigner.FullName
}

try {
    Write-Stage "本地 build-release 预检：$Mode"
    Write-Host "工程：$projectRoot"
    Write-Host "日志：$script:LogDirectory"

    $script:ProjectText = Get-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Raw -Encoding UTF8
    $version = Get-ProjectSetting "config/version"
    $baseId = Get-ProjectSetting "base_id"
    $repository = Get-ProjectSetting "github_repository"
    if ($baseId -notmatch "^[A-Za-z0-9_.-]+$") {
        throw "base_id 含有不安全字符：$baseId"
    }
    if ($Mode -eq "Patch") {
        if ($PatchVersion -notmatch "^\d+\.\d+\.\d+$") {
            throw "Patch 模式必须传入三段版本号，例如 -PatchVersion 1.0.5。"
        }
        if ($BaselinePath -eq "") {
            $BaselinePath = Join-Path $projectRoot "build\update_baselines\$baseId"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $BaselinePath "baseline.json") -PathType Leaf)) {
            throw "补丁基线缺失：$BaselinePath\baseline.json"
        }
    }
    Write-Host "工程版本：$version；基线：$baseId；仓库：$repository"

    $godotCandidates = @(
        (Join-Path $env:USERPROFILE "Desktop\Godot_v4.7.2-stable_win64.exe"),
        (Join-Path $env:USERPROFILE "Desktop\Godot_v4.7.2-stable.exe"),
        "godot.exe",
        "godot"
    )
    $godot = Resolve-File $GodotPath $godotCandidates "Godot 4.7.2"
    $godotVersion = (& $godot --version 2>&1 | Out-String).Trim()
    if ($godotVersion -notmatch "^4\.7\.2\.stable") {
        throw "Godot 版本不匹配：$godotVersion；云端使用 4.7.2-stable。"
    }
    Write-Host "Godot：$godotVersion ($godot)"
    Check-GodotEditorClosed

    $pythonCandidates = @(
        (Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"),
        "python.exe",
        "python",
        "py.exe",
        "py"
    )
    $script:PythonExecutable = Resolve-File "" $pythonCandidates "Python 3"
    $script:PythonPrefix = @()
    if ([IO.Path]::GetFileName($script:PythonExecutable) -in @("py.exe", "py")) {
        $script:PythonPrefix = @("-3")
    }
    $pythonVersion = (& $script:PythonExecutable @($script:PythonPrefix + @("--version")) 2>&1 | Out-String).Trim()
    if ($pythonVersion -notmatch "Python 3\.") {
        throw "Python 版本不受支持：$pythonVersion"
    }
    Write-Host "Python：$pythonVersion ($script:PythonExecutable)"

    Write-Stage "导入工程"
    Invoke-LoggedStep -Name "import" -FilePath $godot -Arguments @("--headless", "--path", $projectRoot, "--editor", "--import")

    Write-Stage "Python 导出配置检查"
    Invoke-PythonStep -Name "configure_tests" -Arguments @("-m", "unittest", "discover", "-s", "tests", "-p", "test_ci_export.py")

    if (-not $SkipCoreTests) {
        Write-Stage "完整 Godot 回归测试（AI 50 局）"
        $oldAiRounds = $env:AI_ROUNDS
        $oldAiMinRounds = $env:AI_MIN_ROUNDS
        $env:AI_ROUNDS = "50"
        $env:AI_MIN_ROUNDS = "50"
        try {
            Invoke-PythonStep -Name "core_tests" -Arguments @("-X", "utf8", "tests/run_suites.py", "--godot", $godot, "--simulation-timeout", "600")
        }
        finally {
            $env:AI_ROUNDS = $oldAiRounds
            $env:AI_MIN_ROUNDS = $oldAiMinRounds
        }
    }
    else {
        Write-Host "已跳过完整 Godot 回归测试（SkipCoreTests）。" -ForegroundColor DarkYellow
    }

    if (-not $SkipNetwork) {
        Write-Stage "网络、联机和断线重连回归"
        Invoke-PythonStep -Name "network_tests" -Arguments @("-X", "utf8", "tests/run_network.py", "--godot", $godot, "--section", "all")
        Invoke-PythonStep -Name "reconnect_tests" -Arguments @("-X", "utf8", "tests/run_reconnect.py", "--godot", $godot)
    }
    else {
        Write-Host "已跳过网络和重连测试（SkipNetwork）。" -ForegroundColor DarkYellow
    }

    if ($Mode -eq "Full") {
        Write-Stage "完整包导出"
        $windows = Join-Path $script:LogDirectory "anshun-mahjong-windows-x64.exe"
        $android = Join-Path $script:LogDirectory "anshun-mahjong.apk"
        $androidSigner = Check-AndroidEnvironment
        Invoke-LoggedStep -Name "export_windows" -FilePath $godot -Arguments @("--headless", "--path", $projectRoot, "--export-release", "Windows", $windows)
        if (-not (Test-Path -LiteralPath $windows -PathType Leaf) -or (Get-Item -LiteralPath $windows).Length -le 0) {
            throw "Windows 导出文件为空：$windows"
        }
        Invoke-LoggedStep -Name "export_android" -FilePath $godot -Arguments @("--headless", "--path", $projectRoot, "--export-release", "Android", $android)
        if (-not (Test-Path -LiteralPath $android -PathType Leaf) -or (Get-Item -LiteralPath $android).Length -le 0) {
            throw "Android 导出文件为空：$android"
        }
        Invoke-LoggedStep -Name "verify_apk" -FilePath $androidSigner -Arguments @("verify", "--verbose", $android)
        $notesPath = Join-Path $script:LogDirectory "release-notes.md"
        Set-Content -LiteralPath $notesPath -Value $Notes -Encoding UTF8
        Invoke-PythonStep -Name "prepare_release" -Arguments @("tools/update/prepare_release.py", "--windows", $windows, "--android", $android, "--output", (Join-Path $script:LogDirectory "releases"), "--repository", $repository, "--notes", $notesPath)
    }
    elseif ($Mode -eq "Patch") {
        Write-Stage "热更新补丁导出"
        Invoke-PythonStep -Name "prepare_patch" -Arguments @("tools/update/prepare_hot_update.py", "patch", "--godot", $godot, "--baseline", (Resolve-Path -LiteralPath $BaselinePath).Path, "--version", $PatchVersion, "--output", (Join-Path $script:LogDirectory "releases"), "--repository", $repository, "--notes", $Notes)
    }

    Write-Host "`n本地 build-release 预检通过，可以提交并运行云端 Build release。" -ForegroundColor Green
    Write-Host "所有日志保存在：$script:LogDirectory" -ForegroundColor Green
    if ($Mode -ne "Check") {
        Write-Host "本地发布文件保存在：$script:LogDirectory\releases" -ForegroundColor Green
    }
    exit 0
}
catch {
    Write-Host "`n本地 build-release 失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "请先修复错误，再运行云端 Build release。" -ForegroundColor Red
    Write-Host "完整日志目录：$script:LogDirectory" -ForegroundColor Yellow
    if ($PauseOnError) {
        Read-Host "按 Enter 关闭窗口"
    }
    exit 1
}


