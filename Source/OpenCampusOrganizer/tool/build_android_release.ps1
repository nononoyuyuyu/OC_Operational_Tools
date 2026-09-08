#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$InitializeSigning,
    [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'OpenCampusOrganizer/Signing'),
    [string]$JavaHome = (Join-Path $env:ProgramFiles 'Android/Android Studio/jbr'),
    [string]$AndroidSdk = (Join-Path $env:LOCALAPPDATA 'Android/Sdk'),
    [string]$OutputDirectory,
    [switch]$SplitPerAbi
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = [IO.Path]::GetFullPath((Join-Path $appRoot '../..'))
$versionText = Get-Content (Join-Path $appRoot 'pubspec.yaml') -Raw
if ($versionText -notmatch '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'バージョンを読み取れません。' }
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
. (Join-Path $PSScriptRoot 'android_apk_layout.ps1')
$apkLayout = @(Get-OcoAndroidApkLayout -SplitPerAbi:$SplitPerAbi)
$SigningDirectory = [IO.Path]::GetFullPath($SigningDirectory)
if ($SigningDirectory.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $SigningDirectory -eq $repoRoot) {
    throw '署名鍵の保存先にはリポジトリ外を指定してください。'
}
$keytool = Join-Path $JavaHome 'bin/keytool.exe'
if (-not (Test-Path -LiteralPath $keytool)) { throw 'Javaのkeytoolが見つかりません。-JavaHomeで指定してください。' }
$keyStore = Join-Path $SigningDirectory 'android-release.jks'
$protectedPassword = Join-Path $SigningDirectory 'android-release.password.dpapi'
$hasStore = Test-Path -LiteralPath $keyStore
$hasPassword = Test-Path -LiteralPath $protectedPassword
if ($hasStore -ne $hasPassword) { throw '署名鍵と暗号化パスワードが揃っていません。既存ファイルを保管し、バックアップから復元してください。' }
if (-not $hasStore -and -not $InitializeSigning) { throw '初回のみ-InitializeSigningを指定して配布用署名鍵を作成してください。' }

$environmentNames = @('JAVA_HOME', 'OCO_ANDROID_STORE_FILE', 'OCO_ANDROID_STORE_PASSWORD', 'OCO_ANDROID_KEY_ALIAS')
$previousEnvironment = @{}
foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:JAVA_HOME = $JavaHome
    $env:OCO_ANDROID_STORE_FILE = $keyStore
    $env:OCO_ANDROID_KEY_ALIAS = 'open-campus-organizer'
    if (-not $hasStore) {
        New-Item -ItemType Directory -Path $SigningDirectory -Force | Out-Null
        $acl = Get-Acl -LiteralPath $SigningDirectory
        $acl.SetAccessRuleProtection($true, $false)
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        foreach ($sid in @($identity, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
        }
        Set-Acl -LiteralPath $SigningDirectory -AclObject $acl
        $env:OCO_ANDROID_STORE_PASSWORD = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
        $securePassword = ConvertTo-SecureString $env:OCO_ANDROID_STORE_PASSWORD -AsPlainText -Force
        ConvertFrom-SecureString $securePassword | Set-Content -LiteralPath $protectedPassword -Encoding ascii
        & $keytool -genkeypair -keystore $keyStore -storetype JKS -alias $env:OCO_ANDROID_KEY_ALIAS -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=Open Campus Organizer' -storepass:env OCO_ANDROID_STORE_PASSWORD -keypass:env OCO_ANDROID_STORE_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw '署名鍵を作成できませんでした。既存ファイルは再生成せず保管してください。' }
    } else {
        $securePassword = (Get-Content -LiteralPath $protectedPassword -Raw).Trim() | ConvertTo-SecureString
        $env:OCO_ANDROID_STORE_PASSWORD = [Net.NetworkCredential]::new('', $securePassword).Password
    }
    & $keytool -list -keystore $keyStore -alias $env:OCO_ANDROID_KEY_ALIAS -storepass:env OCO_ANDROID_STORE_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw '保存済み署名鍵を開けません。' }

    Push-Location $appRoot
    try {
        & flutter pub get --enforce-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Flutter依存関係の取得に失敗しました。' }
        $buildArguments = @('build', 'apk', '--release', '--no-pub')
        if ($SplitPerAbi) { $buildArguments += '--split-per-abi' }
        & flutter @buildArguments
        if ($LASTEXITCODE -ne 0) { throw 'Android Releaseビルドに失敗しました。' }
        $buildTools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
        if (-not $buildTools) { throw 'Android SDK Build Toolsがありません。' }
        # Validate every expected APK before copying any of them to distribution.
        foreach ($apk in $apkLayout) {
            $builtApk = Join-Path 'build/app/outputs/flutter-apk' $apk.Source
            if (-not (Test-Path -LiteralPath $builtApk -PathType Leaf)) { throw "APKが見つかりません: $($apk.Source)" }
            & (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs $builtApk
            if ($LASTEXITCODE -ne 0) { throw "APKの署名を検証できませんでした: $($apk.Source)" }
            $badging = & (Join-Path $buildTools.FullName 'aapt.exe') dump badging $builtApk
            if ($LASTEXITCODE -ne 0 -or ($badging -join "`n") -match 'application-debuggable') {
                throw "配布APKの検証に失敗しました: $($apk.Source)"
            }
            Assert-OcoAndroidApkVersion -Badging $badging -VersionName $appVersion -VersionCode $buildNumber
        }
    } finally { Pop-Location }
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
    if (Get-Variable securePassword -ErrorAction SilentlyContinue) { $securePassword.Dispose() }
}

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "artifacts/release/$appVersion" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($apk in $apkLayout) {
    $apkPath = Join-Path $OutputDirectory "OpenCampusOrganizer-$appVersion-$($apk.Suffix)"
    Copy-Item -LiteralPath (Join-Path $appRoot "build/app/outputs/flutter-apk/$($apk.Source)") -Destination $apkPath
    Get-FileHash -LiteralPath $apkPath -Algorithm SHA256
}
