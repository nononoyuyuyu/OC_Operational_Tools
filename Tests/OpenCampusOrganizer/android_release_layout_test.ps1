#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tool = Join-Path $root 'Source/OpenCampusOrganizer/tool'
. (Join-Path $tool 'android_apk_layout.ps1')
$single = @(Get-OcoAndroidApkLayout)
if ($single.Count -ne 1 -or $single[0].Source -ne 'app-release.apk' -or $single[0].Suffix -ne 'android.apk') {
    throw '従来の単一APKレイアウトが変わっています。'
}
$split = @(Get-OcoAndroidApkLayout -SplitPerAbi)
if ($split.Count -ne 3 -or (@($split.Source | Select-Object -Unique)).Count -ne 3) { throw '分割出力は一意の3件が必要です。' }
foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
    $item = @($split | Where-Object Source -eq "app-$abi-release.apk")
    if ($item.Count -ne 1 -or $item[0].Suffix -ne "android-$abi.apk") { throw "ABI名が一致しません: $abi" }
}
foreach ($name in @('android_apk_layout.ps1', 'build_android_release.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $tool $name), [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw ($errors | Out-String) }
}
Assert-OcoAndroidApkVersion -Badging "package: name='jp.nononoyuyuyu.open_campus_organizer' versionCode='10' versionName='0.4.1' platformBuildVersionCode='37'" -VersionName '0.4.1' -VersionCode '10'
foreach ($invalid in @(
    "package: name='jp.nononoyuyuyu.open_campus_organizer' versionCode='2010' versionName='0.4.1'",
    "package: name='jp.nononoyuyuyu.open_campus_organizer' versionCode='10' versionName='0.4.0'",
    "package: name='different.application' versionCode='10' versionName='0.4.1'",
    'unexpected output'
)) {
    $rejected = $false
    try { Assert-OcoAndroidApkVersion -Badging $invalid -VersionName '0.4.1' -VersionCode '10' }
    catch { $rejected = $true }
    if (-not $rejected) { throw '異なるアプリIDまたはバージョンのAPKを拒否できませんでした。' }
}
Write-Output 'Android APKレイアウト・PowerShell構文: PASS（ビルド・署名鍵操作なし）'
