$ErrorActionPreference = 'Stop'
$updateTarget = @@TARGET@@
$updateSource = @@SOURCE@@
$updateHash = @@SHA256@@
$updatePid = @@PID@@
$updateVersion = @@VERSION@@
$updateBackup = $updateTarget + '.previous'
$updateStage = $updateTarget + '.update-new'
$updateLog = Join-Path ([System.IO.Path]::GetDirectoryName($updateSource)) 'update-result.txt'
$updateMoved = $false
function Get-UpdateHash([string]$updatePath) {
    $updateStream = [System.IO.File]::OpenRead($updatePath)
    $updateHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($updateHasher.ComputeHash($updateStream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $updateHasher.Dispose()
        $updateStream.Dispose()
    }
}
try {
    # The old process must release the embedded PCK executable before replacing it.
    if (Get-Process -Id $updatePid -ErrorAction SilentlyContinue) {
        Wait-Process -Id $updatePid -Timeout 60 -ErrorAction Stop
    }
    if ((Get-UpdateHash $updateSource) -ne $updateHash) {
        throw '更新文件校验失败，未替换旧版本。'
    }
    if ([System.IO.Path]::GetDirectoryName($updateTarget) -eq [System.IO.Path]::GetDirectoryName($updateSource)) {
        throw '更新源文件不能与安装文件在同一目录。'
    }
    # Copy to the installation disk first, so replacing the executable is a rename.
    Copy-Item -LiteralPath $updateSource -Destination $updateStage -Force
    if ((Get-UpdateHash $updateStage) -ne $updateHash) {
        throw '更新副本校验失败，未替换旧版本。'
    }
    for ($updateAttempt = 0; $updateAttempt -lt 20; $updateAttempt++) {
        try {
            if (Test-Path -LiteralPath $updateBackup) { Remove-Item -LiteralPath $updateBackup -Force }
            Move-Item -LiteralPath $updateTarget -Destination $updateBackup -Force
            $updateMoved = $true
            break
        } catch {
            if ($updateAttempt -eq 19) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    Move-Item -LiteralPath $updateStage -Destination $updateTarget -Force
    Start-Process -FilePath $updateTarget -WorkingDirectory ([System.IO.Path]::GetDirectoryName($updateTarget)) -WindowStyle Hidden
    "已更新至 $updateVersion。旧版本保留在 $updateBackup" | Set-Content -LiteralPath $updateLog -Encoding UTF8
} catch {
    $updateError = $_.Exception.Message
    if ($updateMoved -and (Test-Path -LiteralPath $updateBackup)) {
        if (Test-Path -LiteralPath $updateTarget) { Remove-Item -LiteralPath $updateTarget -Force }
        Move-Item -LiteralPath $updateBackup -Destination $updateTarget -Force
    }
    "自动更新失败：$updateError`r`n下载文件：$updateSource`r`n原版本：$updateTarget" | Set-Content -LiteralPath $updateLog -Encoding UTF8
    if (Test-Path -LiteralPath $updateTarget) {
        Start-Process -FilePath $updateTarget -WorkingDirectory ([System.IO.Path]::GetDirectoryName($updateTarget)) -WindowStyle Hidden
    }
    Start-Process -FilePath 'notepad.exe' -ArgumentList @($updateLog) -WindowStyle Hidden
} finally {
    if (Test-Path -LiteralPath $updateStage) { Remove-Item -LiteralPath $updateStage -Force -ErrorAction SilentlyContinue }
}
