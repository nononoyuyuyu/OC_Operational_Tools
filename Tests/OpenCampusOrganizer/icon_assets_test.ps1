$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Source/OpenCampusOrganizer'))
$hashes = @()
foreach ($theme in @('dark', 'light', 'warm', 'sage', 'orange')) {
    $path = Join-Path $appRoot "windows/runner/resources/app_$theme.ico"
    $hashes += (Get-FileHash $path).Hash
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($path))
    try {
        if ($reader.ReadUInt16() -ne 0 -or $reader.ReadUInt16() -ne 1 -or $reader.ReadUInt16() -ne 9) { throw "ICOの構成不正: $theme" }
        foreach ($size in @(16, 20, 24, 32, 40, 48, 64, 128, 256)) {
            $width = $reader.ReadByte(); $height = $reader.ReadByte()
            $expected = if ($size -eq 256) { 0 } else { $size }
            if ($width -ne $expected -or $height -ne $expected) { throw "ICOの寸法不正: $theme" }
            $reader.ReadBytes(6) | Out-Null
            $length = $reader.ReadUInt32(); $offset = $reader.ReadUInt32()
            if ($offset + $length -gt $reader.BaseStream.Length) { throw 'ICOフレームの切断' }
        }
    } finally { $reader.Dispose() }
}
if (($hashes | Select-Object -Unique).Count -ne 5) { throw '配色アイコンが重複しています。' }
$androidHashes = @()
foreach ($theme in @('dark', 'light', 'warm', 'sage', 'orange')) {
    foreach ($density in @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}.GetEnumerator()) {
        $path = Join-Path $appRoot "android/app/src/main/res/mipmap-$($density.Key)/ic_launcher_$theme.png"
        $bitmap = [Drawing.Bitmap]::new($path)
        try {
            if ($bitmap.Width -ne $density.Value -or $bitmap.Height -ne $density.Value -or $bitmap.GetPixel(0, 0).A -ne 0) { throw "Androidの寸法・透過不正: $theme" }
        } finally { $bitmap.Dispose() }
        if ($density.Key -eq 'xxxhdpi') { $androidHashes += (Get-FileHash $path).Hash }
    }
}
if (($androidHashes | Select-Object -Unique).Count -ne 5) { throw 'Androidの配色アイコンが重複しています。' }
$iosRoot = Join-Path $appRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$contents = Get-Content (Join-Path $iosRoot 'Contents.json') -Raw | ConvertFrom-Json
foreach ($entry in $contents.images) {
    $bitmap = [Drawing.Bitmap]::new((Join-Path $iosRoot $entry.filename))
    try {
        $expected = [int]([double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x')))
        if ($bitmap.Width -ne $expected -or $bitmap.Height -ne $expected) { throw 'iOS用寸法不正' }
        if ([Drawing.Image]::IsAlphaPixelFormat($bitmap.PixelFormat)) { throw 'iOS用画像にアルファチャンネルが含まれています。' }
    } finally { $bitmap.Dispose() }
}
foreach ($relative in @('web/icons/Icon-512.png', 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', 'android/app/src/main/res/drawable-xxxhdpi/ic_stat_oco.png')) {
    $bitmap = [Drawing.Bitmap]::new((Join-Path $appRoot $relative))
    try { if ($bitmap.GetPixel(0, 0).A -ne 0) { throw "背景の四隅が透明ではありません: $relative" } }
    finally { $bitmap.Dispose() }
}
Write-Output 'PASS: 5色×9サイズのICO、iOS全サイズとRGB、円形・通知画像の透過'
