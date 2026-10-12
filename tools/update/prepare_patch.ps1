param([string]$Version = "", [string]$Notes = "")
$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $projectDirectory
$pythonRuntime = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path -LiteralPath $pythonRuntime)) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $pythonCommand) { throw "未找到 Python，请安装 Python 3.11 或更新版本。" }
    $pythonRuntime = $pythonCommand.Source
}
$godotRuntime = Join-Path $env:USERPROFILE 'Desktop/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $godotRuntime)) { throw "未找到 Godot 4.7.2，请先修改此文件中的 godotRuntime 路径。" }
$projectText = Get-Content -LiteralPath 'project.godot' -Raw -Encoding UTF8
$baseMatch = [regex]::Match($projectText, '(?m)^base_id="([^"]+)"')
if (-not $baseMatch.Success) { throw "工程未配置热更新基线 ID。" }
$tagMatch = [regex]::Match($projectText, '(?m)^tag_prefix="([vV]?)"')
$tagPrefix = if ($tagMatch.Success) { $tagMatch.Groups[1].Value } else { "v" }
$baselineDirectory = Join-Path $projectDirectory ('build/update_baselines/' + $baseMatch.Groups[1].Value)
if (-not (Test-Path -LiteralPath (Join-Path $baselineDirectory 'baseline.json'))) { throw "热更新基线缺失，请恢复基线备份。" }
if ($Version -eq "") { $Version = Read-Host "输入新小版本号（如 1.0.1，下次 1.0.2）" }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "版本号应为三段数字，例如 1.0.1。" }
if ($Notes -eq "") { $Notes = Read-Host "输入本次更新说明" }
$releaseFolder = Join-Path $projectDirectory ('build/releases/v' + $Version)
if (Test-Path -LiteralPath $releaseFolder) { throw "此版本目录已存在。请使用新的版本号，避免覆盖已发布文件。" }
& $pythonRuntime 'tools/update/prepare_hot_update.py' patch --godot $godotRuntime --baseline $baselineDirectory --version $Version --notes $Notes
if ($LASTEXITCODE -ne 0) { throw "生成失败，请查看上面的提示与发布目录日志。" }
Write-Host "生成完成。将此目录的两个 PCK 和 update-manifest.json 上传到 GitHub 的 $tagPrefix$Version Release。"
Start-Process -FilePath explorer.exe -ArgumentList $releaseFolder
