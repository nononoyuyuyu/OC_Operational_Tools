param([switch]$WindowsOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$paletteSource = Get-Content -LiteralPath (Join-Path $appRoot 'lib/design/color_schemes.dart') -Raw
$iconDirectory = Join-Path $appRoot 'windows/runner/resources'
$palettes = [regex]::Matches($paletteSource, '(?s)AppAppearance\.(dark|light|warm|sage|orange): _Palette\((.*?)\),')
if ($palettes.Count -ne 5) { throw '配色定義を読み取れません。' }

# 生成原画を配色と各OSのサイズ・形式へ変換する。形は描き直さない。
$master = [Drawing.Bitmap]::new((Join-Path $appRoot 'assets/branding/oco-master.png'))
function New-IconBitmap([int]$size, [Drawing.Color]$foreground, [Drawing.Color]$background, [string]$shape = 'circle') {
    $bitmap = [Drawing.Bitmap]::new($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $attributes = [Drawing.Imaging.ImageAttributes]::new()
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $matrix = [Drawing.Imaging.ColorMatrix]::new()
        $matrix.Matrix00 = ($foreground.R - $background.R) / 255.0
        $matrix.Matrix01 = ($foreground.G - $background.G) / 255.0
        $matrix.Matrix02 = ($foreground.B - $background.B) / 255.0
        $matrix.Matrix40 = $background.R / 255.0
        $matrix.Matrix41 = $background.G / 255.0
        $matrix.Matrix42 = $background.B / 255.0
        $matrix.Matrix11 = 0; $matrix.Matrix22 = 0
        if ($shape -eq 'foreground') {
            $matrix.Matrix00 = 0; $matrix.Matrix01 = 0; $matrix.Matrix02 = 0
            $matrix.Matrix40 = $foreground.R / 255.0
            $matrix.Matrix41 = $foreground.G / 255.0
            $matrix.Matrix42 = $foreground.B / 255.0
            $matrix.Matrix03 = 1; $matrix.Matrix33 = 0
        }
        $attributes.SetColorMatrix($matrix)
        if ($shape -eq 'circle') {
            $path.AddEllipse([single]1, [single]1, [single]($size - 2), [single]($size - 2))
            $graphics.SetClip($path)
        }
        $graphics.DrawImage($master, [Drawing.Rectangle]::new(0, 0, $size, $size), 0, 0, $master.Width, $master.Height, [Drawing.GraphicsUnit]::Pixel, $attributes)
    } finally { $path.Dispose(); $attributes.Dispose(); $graphics.Dispose() }
    return $bitmap
}

function Save-Png([string]$relative, [int]$size, [string]$shape = 'square', [Drawing.Color]$foreground = $script:darkForeground, [Drawing.Color]$background = $script:darkBackground) {
    $destination = Join-Path $appRoot $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    $large = New-IconBitmap ($size * 2) $foreground $background $shape
    $format = if ($shape -eq 'square') { [Drawing.Imaging.PixelFormat]::Format24bppRgb } else { [Drawing.Imaging.PixelFormat]::Format32bppArgb }
    $bitmap = [Drawing.Bitmap]::new($size, $size, $format)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($large, 0, 0, $size, $size)
    $graphics.Dispose()
    try { $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose(); $large.Dispose() }
}

try {
foreach ($palette in $palettes) {
    $themeName = $palette.Groups[1].Value
    $colors = $palette.Groups[2].Value
    $foregroundHex = [regex]::Match($colors, 'primary: 0xff([0-9a-f]{6})').Groups[1].Value
    $backgroundHex = [regex]::Match($colors, 'paper: 0xff([0-9a-f]{6})').Groups[1].Value
    $foreground = [Drawing.ColorTranslator]::FromHtml("#$foregroundHex")
    $background = [Drawing.ColorTranslator]::FromHtml("#$backgroundHex")
    if ($themeName -eq 'dark') { $script:darkForeground = $foreground; $script:darkBackground = $background }
    $frames = @()
    foreach ($size in @(16, 20, 24, 32, 40, 48, 64, 128, 256)) {
        $canvasSize = $size * 4
        $bitmap = New-IconBitmap $canvasSize $foreground $background
        $resized = [Drawing.Bitmap]::new($size, $size)
        $resizer = [Drawing.Graphics]::FromImage($resized)
        $resizer.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $resizer.DrawImage($bitmap, 0, 0, $size, $size)
        $stream = [IO.MemoryStream]::new()
        $resized.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        $frames += @{ Size = $size; Bytes = $stream.ToArray() }
        $stream.Dispose()
        $resizer.Dispose()
        $resized.Dispose()
        $bitmap.Dispose()
    }
    $iconPath = Join-Path $iconDirectory "app_$themeName.ico"
    $output = [IO.File]::Create($iconPath)
    $writer = [IO.BinaryWriter]::new($output)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    } finally {
        $writer.Dispose()
        $output.Dispose()
    }
    Write-Output $iconPath
    if (!$WindowsOnly) {
        $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
        foreach ($density in $densities.Keys) {
            $pixels = $densities[$density]
            Save-Png "android/app/src/main/res/mipmap-$density/ic_launcher_$themeName.png" $pixels 'circle' $foreground $background
            Save-Png "android/app/src/main/res/drawable-$density/ic_launcher_${themeName}_foreground.png" ([int]($pixels * 108 / 48)) 'foreground' $foreground $background
        }
        $adaptive = Join-Path $appRoot "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_$themeName.xml"
        [IO.File]::WriteAllText($adaptive, @"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/launcher_$themeName" />
    <foreground android:drawable="@drawable/ic_launcher_${themeName}_foreground" />
</adaptive-icon>
"@)
        $colorPath = Join-Path $appRoot "android/app/src/main/res/values/launcher_$themeName.xml"
        [IO.File]::WriteAllText($colorPath, "<resources><color name=`"launcher_$themeName`">#$backgroundHex</color></resources>`n")
    }
}
if (!$WindowsOnly) {
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($density in $densities.Keys) {
        $pixels = $densities[$density]
        Save-Png "android/app/src/main/res/mipmap-$density/ic_launcher.png" $pixels 'circle'
        Save-Png "android/app/src/main/res/drawable-$density/ic_launcher_foreground.png" ([int]($pixels * 108 / 48)) 'foreground'
        Save-Png "android/app/src/main/res/drawable-$density/ic_stat_oco.png" ([int]($pixels / 2)) 'foreground' ([Drawing.Color]::White)
    }
    $iconset = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    $contents = Get-Content (Join-Path $appRoot "$iconset/Contents.json") -Raw | ConvertFrom-Json
    foreach ($entry in $contents.images) {
        $pixels = [int]([double]($entry.size.Split('x')[0]) * [double]($entry.scale.TrimEnd('x')))
        Save-Png "$iconset/$($entry.filename)" $pixels
    }
    foreach ($pixels in @(192, 512)) {
        Save-Png "web/icons/Icon-$pixels.png" $pixels 'circle'
        Save-Png "web/icons/Icon-maskable-$pixels.png" $pixels
    }
    Save-Png 'web/favicon.png' 32 'circle'
    Write-Output 'Android・iOS・Web: 完了'
}
} finally { $master.Dispose() }
