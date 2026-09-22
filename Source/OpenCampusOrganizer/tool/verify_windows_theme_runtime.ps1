param(
    [Parameter(Mandatory = $true)][string]$ExpectedExecutable,
    [int]$TargetProcessId = 0
)

$ErrorActionPreference = 'Stop'
# 実表示テストの前提確認。設定・資格情報・ログ・ウィンドウには触れない。
$expected = Get-Item -LiteralPath $ExpectedExecutable
if ($expected.PSIsContainer -or $expected.Name -ne 'open_campus_organizer.exe') {
    throw '検証対象のopen_campus_organizer.exeを指定してください。'
}
$candidates = @(Get-Process -Name 'open_campus_organizer' -ErrorAction SilentlyContinue |
    Where-Object { $TargetProcessId -eq 0 -or $_.Id -eq $TargetProcessId })
if ($candidates.Count -ne 1) {
    throw '起動中の対象アプリを1個に絞れません。起動してTargetProcessIdを指定してください。'
}
$running = $candidates[0]
$started = $running.StartTime.ToUniversalTime()
$actual = Get-Item -LiteralPath $running.Path
$expectedHash = (Get-FileHash -LiteralPath $expected.FullName -Algorithm SHA256).Hash
$actualHash = (Get-FileHash -LiteralPath $actual.FullName -Algorithm SHA256).Hash
if ($actual.LastWriteTimeUtc -gt $started) {
    throw '実行開始後にEXEが変更されています。アプリを正常終了して起動し直してください。'
}
$running.Refresh()
if ($running.HasExited) { throw '照合中に対象アプリが終了しました。' }
$matches = $actualHash -eq $expectedHash
[ordered]@{
    capturedUtc = [DateTime]::UtcNow.ToString('o')
    processId = $running.Id
    startedUtc = $started.ToString('o')
    runtimePath = $actual.FullName
    runtimeVersion = $actual.VersionInfo.ProductVersion
    runtimeSha256 = $actualHash
    expectedVersion = $expected.VersionInfo.ProductVersion
    expectedSha256 = $expectedHash
    binaryMatches = $matches
    shellDisplayVerified = $false
} | ConvertTo-Json
if (-not $matches) {
    throw '起動中のアプリは修正候補と異なります。この状態の表示結果を修正候補の検証として扱わないでください。'
}
