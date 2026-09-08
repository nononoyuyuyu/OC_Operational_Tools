# 既存のWindows専用コマンドは共通処理へ委譲する。
& (Join-Path $PSScriptRoot 'generate_icons.ps1') -WindowsOnly
