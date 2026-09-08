#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$CompilerPath,
    [string]$OutputDirectory,
    [string]$DependencyCache,
    [string]$UserDataTestRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = [IO.Path]::GetFullPath((Join-Path $appRoot '../..'))
$configuration = Get-Content (Join-Path $appRoot 'installer/windows/dependencies.json') -Raw | ConvertFrom-Json
$versionText = Get-Content (Join-Path $appRoot 'pubspec.yaml') -Raw
if ($versionText -notmatch '(?m)^version: (\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'pubspec.yamlのバージョンを読み取れません。'
}
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot "artifacts/release/$appVersion" }
if (-not $DependencyCache) { $DependencyCache = Join-Path $repoRoot 'artifacts/release-tools' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$DependencyCache = [IO.Path]::GetFullPath($DependencyCache)
if ($UserDataTestRoot) {
    if ($UserDataTestRoot -match "['\r\n]") { throw '検証用パスに使用できない文字があります。' }
    $UserDataTestRoot = [IO.Path]::GetFullPath($UserDataTestRoot)
    $allowedTestRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')) + [IO.Path]::DirectorySeparatorChar
    if (-not $UserDataTestRoot.StartsWith($allowedTestRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw '検証用データの保存先はリポジトリ内のartifactsに限定します。'
    }
}
New-Item -ItemType Directory -Path $OutputDirectory, $DependencyCache -Force | Out-Null

if (-not $CompilerPath) {
    $compilerCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/Inno Setup 7/ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 7/ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7/ISCC.exe')
    )
    $CompilerPath = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $CompilerPath -or -not (Test-Path -LiteralPath $CompilerPath)) {
    throw 'Inno Setup 7.1.0を導入するか、-CompilerPathでISCC.exeを指定してください。'
}
$compilerVersion = & $CompilerPath --version
if ($LASTEXITCODE -ne 0 -or ($compilerVersion -join ' ') -notmatch [regex]::Escape($configuration.innoSetupVersion)) {
    throw "Inno Setup $($configuration.innoSetupVersion)が必要です。"
}

$runtime = $configuration.vcRedist
$runtimePath = Join-Path $DependencyCache 'vc_redist.x64.exe'
if (-not (Test-Path -LiteralPath $runtimePath)) {
    Invoke-WebRequest $runtime.url -OutFile $runtimePath
}
if ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash -ne $runtime.sha256) {
    throw 'VC++再頒布パッケージのハッシュが一致しません。キャッシュとdependencies.jsonを確認してください。'
}
$signature = Get-AuthenticodeSignature -LiteralPath $runtimePath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation,') {
    throw 'VC++再頒布パッケージのMicrosoft署名を確認できません。'
}
$runtimeVersion = [version](Get-Item -LiteralPath $runtimePath).VersionInfo.FileVersion
if ($runtimeVersion -ne [version]$runtime.version) { throw 'VC++のファイルバージョンが一致しません。' }

Push-Location $appRoot
try {
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Flutter依存関係の取得に失敗しました。' }
    & flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Windowsビルドに失敗しました。' }
} finally { Pop-Location }

$appBuildDir = Join-Path $appRoot 'build/windows/x64/runner/Release'
$exePath = Join-Path $appBuildDir 'open_campus_organizer.exe'
if ((Get-Item -LiteralPath $exePath).VersionInfo.ProductVersion -notlike "$appVersion*") {
    throw 'ビルド結果のバージョンが一致しません。'
}
$compilerFiles = @(Get-ChildItem (Join-Path $appRoot 'build/windows/x64/CMakeFiles') -Filter CMakeCXXCompiler.cmake -Recurse)
foreach ($compilerFile in $compilerFiles) {
    $compilerText = Get-Content -LiteralPath $compilerFile.FullName -Raw
    # cl.exe本体の19.xと再頒布パッケージの14.xは末尾の更新番号が異なる。
    # CMakeが選んだ実際のMSVCツールセットの版を比較する。
    if ($compilerText -match 'set\(CMAKE_CXX_COMPILER "[^"\r\n]*[/\\]MSVC[/\\](14\.\d+\.\d+(?:\.\d+)?)[/\\]') {
        $requiredRuntime = [version]$Matches[1]
        Write-Host "MSVCツールセット: $requiredRuntime / 同梱ランタイム: $runtimeVersion"
        if ($requiredRuntime -gt $runtimeVersion) {
            throw "ビルド環境に対してVC++ランタイムが古すぎます。dependencies.jsonを更新してください（必要: $requiredRuntime）。"
        }
    } else { throw 'MSVCのバージョンを確認できません。' }
}
if ($compilerFiles.Count -eq 0) { throw 'MSVCのビルド情報がありません。' }
$compilerArguments = @(
    '--quiet', "--define=AppVersion=$appVersion", "--define=AppBuildNumber=$buildNumber",
    "--define=OutputDirectory=$OutputDirectory", "--define=AppBuildDir=$appBuildDir",
    "--define=VcRedistPath=$runtimePath", "--define=VcRuntimeMajor=$($runtimeVersion.Major)",
    "--define=VcRuntimeMinor=$($runtimeVersion.Minor)", "--define=VcRuntimeBuild=$($runtimeVersion.Build)",
    "--define=VcRuntimeRevision=$($runtimeVersion.Revision)",
    (Join-Path $appRoot 'installer/windows/OpenCampusOrganizer.iss')
)
if ($UserDataTestRoot) { $compilerArguments = @("--define=OcoTestDataRoot=$UserDataTestRoot") + $compilerArguments }
& $CompilerPath @compilerArguments
if ($LASTEXITCODE -ne 0) { throw 'Windowsインストーラーの作成に失敗しました。' }
$installer = Join-Path $OutputDirectory "OpenCampusOrganizer-$appVersion-windows-x64-setup.exe"
if ($UserDataTestRoot) { $installer = Join-Path $OutputDirectory 'OpenCampusOrganizer-userdata-test-setup.exe' }
if ($UserDataTestRoot) {
    @{ TestDataRoot = $UserDataTestRoot; InstallerSHA256 = (Get-FileHash -LiteralPath $installer).Hash } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'userdata-test.json') -Encoding utf8
}
Get-FileHash -LiteralPath $installer -Algorithm SHA256
