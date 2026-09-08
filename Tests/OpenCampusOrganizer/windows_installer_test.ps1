#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Installer,
    [string]$BuildDirectory = (Join-Path $PSScriptRoot '../../Source/OpenCampusOrganizer/build/windows/x64/runner/Release')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
$testRoot = Join-Path $artifactRoot ('installer-test-' + [guid]::NewGuid().ToString('N'))
$installDirectory = Join-Path $testRoot 'application'
$groupName = 'OCO-installer-test-' + [guid]::NewGuid().ToString('N')
$groupDirectory = Join-Path ([Environment]::GetFolderPath('Programs')) $groupName
$shortcutPath = Join-Path $groupDirectory 'Open Campus Organizer.lnk'
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$registrySuffix = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D4EBAB8B-0A55-489B-A9E1-BF65C0C96CD4}_is1'
foreach ($hive in @('HKCU:', 'HKLM:')) {
    if (Test-Path "$hive\$registrySuffix") { throw '既存のインストールがあります。検証は未導入のWindowsユーザーで行ってください。' }
}
$Installer = (Resolve-Path -LiteralPath $Installer).Path
$BuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
if (-not $testRoot.StartsWith($artifactRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '検証先がartifactsの外にあります。'
}
New-Item -ItemType Directory -Path $testRoot | Out-Null
$sourceFiles = @(Get-ChildItem -LiteralPath $BuildDirectory -File -Recurse | Where-Object Extension -ne '.pdb')

function Install-And-Verify([string]$LogName) {
    $installArguments = @('/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/GROUP="' + $groupName + '"'),
        ('/DIR="' + $installDirectory + '"'), ('/LOG="' + (Join-Path $testRoot $LogName) + '"'))
    $process = Start-Process -FilePath $Installer -ArgumentList $installArguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "インストール失敗: $($process.ExitCode)。ログ: $testRoot" }
    $registration = Get-ItemProperty "HKCU:\$registrySuffix"
    if ($registration.InstallLocation.TrimEnd('\') -ne $installDirectory) { throw 'インストールの登録先が一致しません。' }
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    if ($shortcut.TargetPath -ne (Join-Path $installDirectory 'open_campus_organizer.exe')) { throw 'スタートメニューの起動先が一致しません。' }
    if (@(Get-ChildItem -LiteralPath $installDirectory -Filter 'unins*.exe').Count -ne 1) { throw '更新でアンインストーラーが重複しました。' }
    foreach ($file in $sourceFiles) {
        $relativePath = [IO.Path]::GetRelativePath($BuildDirectory, $file.FullName)
        $installedFile = Join-Path $installDirectory $relativePath
        if ((Get-FileHash -LiteralPath $installedFile).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
            throw "配布ファイルの不一致: $relativePath"
        }
    }
}

Install-And-Verify 'install.log'
$preservedFile = Join-Path $installDirectory 'user-created-file.txt'
'OCOの検証用データ' | Set-Content -LiteralPath $preservedFile -Encoding utf8
Install-And-Verify 'reinstall.log'
if (@(Select-String -LiteralPath (Join-Path $testRoot 'reinstall.log') -Pattern 'Will append to existing uninstall log').Count -eq 0) { throw '既存のインストールとして更新されていません。' }
# 別フォルダーへの二重導入で既存のアンインストール登録を失わない。
$otherDirectory = Join-Path $testRoot 'other-application'
$otherLog = Join-Path $testRoot 'other-directory.log'
$other = Start-Process -FilePath $Installer -ArgumentList @('/CURRENTUSER', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $otherDirectory + '"'), ('/LOG="' + $otherLog + '"')) -WindowStyle Hidden -Wait -PassThru
if ($other.ExitCode -eq 0 -or (Test-Path -LiteralPath (Join-Path $otherDirectory 'open_campus_organizer.exe'))) { throw '別フォルダーへの二重導入を拒否できませんでした。' }
if (@(Select-String -LiteralPath $otherLog -SimpleMatch 'OCO: blocked different install directory.').Count -eq 0) { throw '保存先の不一致による拒否ではありません。' }
if ((Get-ItemProperty "HKCU:\$registrySuffix").InstallLocation.TrimEnd('\') -ne $installDirectory) { throw '二重導入の拒否で登録先が変わりました。' }
if (-not (Test-Path -LiteralPath $preservedFile)) { throw '再インストールでユーザーファイルが失われました。' }

function Assert-ScopeBlocked([string]$Mode, [string]$LogName) {
    $scopeLog = Join-Path $testRoot $LogName
    $attempt = Start-Process -FilePath $Installer -ArgumentList @($Mode, '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', ('/DIR="' + $installDirectory + '"'), ('/LOG="' + $scopeLog + '"')) -WindowStyle Hidden -Wait -PassThru
    if ($attempt.ExitCode -eq 0 -or @(Select-String -LiteralPath $scopeLog -SimpleMatch 'OCO: blocked different install scope.').Count -eq 0) { throw '反対側のインストール対象を拒否できませんでした。' }
}
if ($isElevated) {
    Assert-ScopeBlocked '/ALLUSERS' 'user-to-machine.log'
    if (Test-Path "HKLM:\$registrySuffix") { throw '全ユーザー側に二重登録されました。' }
}

# アンインストーラーの実行直前に、実在する絶対パスと登録先を再確認する。
$resolvedInstall = (Resolve-Path -LiteralPath $installDirectory).Path
if (-not $resolvedInstall.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'アンインストール先が検証用ディレクトリ外です。'
}
if ((Get-ItemProperty "HKCU:\$registrySuffix").InstallLocation.TrimEnd('\') -ne $resolvedInstall) {
    throw 'アンインストールの登録先が変化しました。'
}
$uninstaller = Join-Path $resolvedInstall 'unins000.exe'
$uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/LOG="' + (Join-Path $testRoot 'uninstall.log') + '"')) -WindowStyle Hidden -Wait -PassThru
if ($uninstallProcess.ExitCode -ne 0) { throw "アンインストール失敗: $($uninstallProcess.ExitCode)" }
if (Test-Path "HKCU:\$registrySuffix") { throw 'アンインストール登録が残っています。' }
foreach ($file in $sourceFiles) {
    if (Test-Path -LiteralPath (Join-Path $installDirectory ([IO.Path]::GetRelativePath($BuildDirectory, $file.FullName)))) {
        throw "配布ファイルが削除されませんでした: $($file.Name)"
    }
}
if (-not (Test-Path -LiteralPath $preservedFile)) { throw 'アンインストールでユーザーファイルが失われました。' }
if (Test-Path -LiteralPath $shortcutPath) { throw 'スタートメニューにショートカットが残っています。' }
if ($isElevated) {
    # CI等の昇格済み環境だけで両方向を実測する。対話的な昇格は要求しない。
    $machine = Start-Process -FilePath $Installer -ArgumentList @('/ALLUSERS', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', ('/DIR="' + $installDirectory + '"')) -WindowStyle Hidden -Wait -PassThru
    if ($machine.ExitCode -ne 0) { throw '全ユーザー向けの検証導入に失敗しました。' }
    if ((Get-ItemProperty "HKLM:\$registrySuffix").InstallLocation.TrimEnd('\') -ne $resolvedInstall) { throw '全ユーザーの登録先が検証範囲外です。' }
    Assert-ScopeBlocked '/CURRENTUSER' 'machine-to-user.log'
    if (Test-Path "HKCU:\$registrySuffix") { throw '現在のユーザー側に二重登録されました。' }
    # 上の登録先と、先に検証したartifacts内の絶対パスが一致した場合のみ削除する。
    $removed = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -WindowStyle Hidden -Wait -PassThru
    if ($removed.ExitCode -ne 0 -or (Test-Path "HKLM:\$registrySuffix")) { throw '全ユーザー向けの検証導入を削除できませんでした。' }
    if (-not (Test-Path -LiteralPath $preservedFile)) { throw '全ユーザー向け削除でユーザーファイルが失われました。' }
} else {
    Write-Output 'SKIP: インストール対象をまたぐ実測は昇格済みCIで実行します。'
}
[pscustomobject]@{Result = 'PASS'; PayloadFiles = $sourceFiles.Count; EvidenceDirectory = $testRoot}
