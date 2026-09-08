#requires -Version 7.0
# Pure output metadata: importing this helper never builds or touches signing data.
function Get-OcoAndroidApkLayout {
    [CmdletBinding()]
    param([switch]$SplitPerAbi)
    if ($SplitPerAbi) {
        foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
            [pscustomobject]@{
                Source = "app-$abi-release.apk"
                Suffix = "android-$abi.apk"
            }
        }
    } else {
        [pscustomobject]@{ Source = 'app-release.apk'; Suffix = 'android.apk' }
    }
}

function Assert-OcoAndroidApkVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Badging,
        [Parameter(Mandatory)][string]$VersionName,
        [Parameter(Mandatory)][string]$VersionCode
    )
    $packageLines = @($Badging | Where-Object { $_ -match '^package: ' })
    if ($packageLines.Count -ne 1 -or
        $packageLines[0] -notmatch "^package: name='jp\.nononoyuyuyu\.open_campus_organizer' versionCode='([^']+)' versionName='([^']+)'(?:\s|$)" -or
        $Matches[1] -cne $VersionCode -or $Matches[2] -cne $VersionName) {
        throw 'APKのアプリIDまたはバージョンがpubspec.yamlと一致しません。'
    }
}
