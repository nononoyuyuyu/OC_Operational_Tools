#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
$Installer = (Resolve-Path -LiteralPath $Installer).Path
if ([IO.Path]::GetFileName($Installer) -ne 'OpenCampusOrganizer-userdata-test-setup.exe') { throw 'データ検証専用インストーラーが必要です。' }
$manifest = Get-Content -LiteralPath (Join-Path (Split-Path $Installer) 'userdata-test.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $Installer).Hash -ne $manifest.InstallerSHA256) { throw '検証専用ビルドのハッシュが一致しません。' }
$testDataRoot = [IO.Path]::GetFullPath($manifest.TestDataRoot)
if (-not $testDataRoot.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '検証データがartifactsの外です。' }
$testRoot = Join-Path $artifactRoot ('userdata-test-' + [guid]::NewGuid().ToString('N'))
$applicationDirectory = Join-Path $testRoot 'application'
$registrationKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D4EBAB8B-0A55-489B-A9E1-BF65C0C96CD4}_is1'
foreach ($hive in @('HKCU:', 'HKLM:')) {
    if (Test-Path "$hive\$registrationKey") { throw '既存のインストールがあります。未導入のWindowsユーザーで実行してください。' }
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$modern = Join-Path $testDataRoot 'jp.nononoyuyuyu/Open Campus Organizer'
$legacy = Join-Path $testDataRoot 'jp.nononoyuyuyu/OC運営用総合ツール'
$modernData = Join-Path $modern 'open_campus_organizer/v1'
$legacyData = Join-Path $legacy 'oc_operations/v1'
$ownedFiles = @((Join-Path $modernData 'app_v1_appearance.data'), (Join-Path $modernData 'kakutei_v1_pending_task.data'),
    (Join-Path $modernData 'kakutei_v1_operation_123.data'), (Join-Path $modern 'flutter_secure_storage.dat'),
    (Join-Path $legacyData 'old.data'), (Join-Path $legacy 'flutter_secure_storage.dat'))
$preservedFiles = @((Join-Path $modern 'user-notes.txt'), (Join-Path $modernData 'manual.txt'))

function Seed-Data {
    New-Item -ItemType Directory -Path $modernData,$legacyData -Force | Out-Null
    foreach ($path in ($ownedFiles + $preservedFiles)) { 'OCOの架空検証データ。資格情報ではありません。' | Set-Content -LiteralPath $path -Encoding utf8 }
}
function Install-Application([string]$DataChoice, [string]$Name, [int]$Expected = 0) {
    $args = @('/CURRENTUSER','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/NOICONS',('/DATA=' + $DataChoice),
        ('/DIR="' + $applicationDirectory + '"'), ('/LOG="' + (Join-Path $testRoot ($Name + '.log')) + '"'))
    $process = Start-Process -FilePath $Installer -ArgumentList $args -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne $Expected) { throw "導入の終了コード: $($process.ExitCode)、期待: $Expected" }
}
function Uninstall-Application([string]$DataChoice, [string]$Name) {
    $resolved = (Resolve-Path -LiteralPath $applicationDirectory).Path
    if (-not $resolved.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '削除先が検証領域外です。' }
    if ((Get-ItemProperty "HKCU:\$registrationKey").InstallLocation.TrimEnd('\') -ne $resolved) { throw 'アンインストール先が一致しません。' }
    $process = Start-Process -FilePath (Join-Path $resolved 'unins000.exe') -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DATA=' + $DataChoice),('/LOG="' + (Join-Path $testRoot ($Name + '.log')) + '"')) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'アンインストールに失敗しました。' }
    if (Test-Path "HKCU:\$registrationKey") { throw '登録が残っています。' }
}
function Assert-Data([bool]$Present) {
    foreach ($path in $ownedFiles) {
        if ((Test-Path -LiteralPath $path) -ne $Present) { throw "管理データの状態が想定と異なります: $path" }
    }
    foreach ($path in $preservedFiles) {
        if (-not (Test-Path -LiteralPath $path)) { throw "利用者の別ファイルが失われました: $path" }
    }
    if (-not $Present -and -not (Test-Path -LiteralPath (Join-Path $modern '.oco_storage_migrated_v1'))) { throw '旧版再取り込みの防止マーカーがありません。' }
}
Seed-Data
$before = @{}; foreach ($path in ($ownedFiles + $preservedFiles)) { $before[$path] = (Get-FileHash -LiteralPath $path).Hash }
Install-Application keep install-keep
Uninstall-Application keep uninstall-keep
Assert-Data $true
foreach ($path in $before.Keys) { if ((Get-FileHash -LiteralPath $path).Hash -ne $before[$path]) { throw '保持を選んだデータが変更されました。' } }
Install-Application reset install-reset
Assert-Data $false
Uninstall-Application keep uninstall-after-reset
Seed-Data
Install-Application keep install-again
Uninstall-Application delete uninstall-delete
Assert-Data $false

# ジャンクションの先にある別データを削除しないことを確認する。
$preservedModern = Join-Path (Split-Path $modern) 'saved-current'
$protectedRoot = Join-Path $testRoot 'protected-data'
foreach ($path in @($modern, $preservedModern, $protectedRoot)) {
    $absolute = [IO.Path]::GetFullPath($path)
    if (-not $absolute.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'リンク検証先が領域外です。' }
}
if (Test-Path -LiteralPath $preservedModern) { throw '退避先が既に存在します。' }
Rename-Item -LiteralPath $modern -NewName 'saved-current'
$protectedFile = Join-Path $protectedRoot 'open_campus_organizer/v1/protected.data'
New-Item -ItemType Directory -Path (Split-Path $protectedFile) -Force | Out-Null
'保持するデータ' | Set-Content -LiteralPath $protectedFile
$protectedHash = (Get-FileHash -LiteralPath $protectedFile).Hash
New-Item -ItemType Junction -Path $modern -Target $protectedRoot | Out-Null
Install-Application reset install-reject-link 20
if ((Get-FileHash -LiteralPath $protectedFile).Hash -ne $protectedHash) { throw 'リンク先のデータが変更されました。' }
Uninstall-Application keep uninstall-link-test
$link = Get-Item -LiteralPath $modern -Force
if ($link.LinkType -ne 'Junction' -or $link.Target -ne $protectedRoot) { throw '検証用リンクが変化しました。' }
Remove-Item -LiteralPath $modern -Force
Rename-Item -LiteralPath $preservedModern -NewName 'Open Campus Organizer'
[pscustomobject]@{ Result = 'PASS'; Cases = '引継ぎ・新規開始・保持・削除・リンク拒否・他ファイル保持'; EvidenceDirectory = $testRoot }
