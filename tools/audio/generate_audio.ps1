param(
    [Parameter(Mandatory = $true)][string]$PythonPath,
    [ValidateSet('Neural', 'Local')][string]$VoiceSource = 'Neural',
    [string]$DependencyDirectory = ''
)
$ErrorActionPreference = 'Stop'
$mahjongRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$voiceDirectory = Join-Path $mahjongRoot 'res/audio/voice'
[System.IO.Directory]::CreateDirectory($voiceDirectory) | Out-Null
if ($VoiceSource -eq 'Neural') {
    $arguments = @((Join-Path $PSScriptRoot 'generate_neural_voice.py'))
    if ($DependencyDirectory) { $arguments += @('--dependency-dir', $DependencyDirectory) }
    & $PythonPath @arguments
    if ($LASTEXITCODE -ne 0) { throw '柔和语音生成失败，现有素材已保留。' }
    Write-Output '完成：四个座位各一套柔和牌名与动作语音、Ripples背景音乐署名和落桌音效。'
    exit 0
}
$speaker = New-Object -ComObject SAPI.SpVoice
$chineseVoice = $speaker.GetVoices() | Where-Object { $_.GetDescription() -match 'Huihui|Chinese.*Simplified' } | Select-Object -First 1
if ($null -eq $chineseVoice) { throw '需要安装 Windows 简体中文语音包后再生成语音。' }
$speaker.Voice = $chineseVoice
$speaker.Rate = -1
$speaker.Volume = 100
$numbers = @('一', '二', '三', '四', '五', '六', '七', '八', '九')
$phrases = [ordered]@{}
foreach ($suit in @('wan', 'tiao', 'tong')) {
    $suffix = @{wan = '万'; tiao = '条'; tong = '筒'}[$suit]
    for ($rank = 1; $rank -le 9; $rank++) {
        $text = $numbers[$rank - 1] + $suffix
        if ($suit -eq 'tiao' -and $rank -eq 1) { $text = '幺鸡' }
        $phrases[$suit + $rank] = $text
    }
}
$phrases['hu'] = '胡了'
$phrases['zimo'] = '自摸'
$phrases['pong'] = '碰'
$phrases['kong'] = '杠'
$phrases['ready'] = '报听'
foreach ($entry in $phrases.GetEnumerator()) {
    $stream = New-Object -ComObject SAPI.SpFileStream
    $format = New-Object -ComObject SAPI.SpAudioFormat
    $format.Type = 22 # 22.05 kHz / 16-bit mono PCM
    $stream.Format = $format
    $stream.Open((Join-Path $voiceDirectory ($entry.Key + '.wav')), 3, $false)
    try {
        $speaker.AudioOutputStream = $stream
        [void]$speaker.Speak($entry.Value)
    } finally { $stream.Close() }
}
& $PythonPath (Join-Path $PSScriptRoot 'generate_assets.py')
if ($LASTEXITCODE -ne 0) { throw '音频处理失败。' }
Write-Output '完成：牌名与动作语音、背景音乐署名和落桌音效。'
