# Open Campus Organizer

オープンキャンパス運営を支援するFlutterアプリです。

このディレクトリで実行します。

```powershell
flutter pub get --enforce-lockfile
flutter run -d windows
```

「確定ロール」を開き、Discordに接続するか「サンプルで試す」を選択してください。

```powershell
flutter analyze
flutter test ../../Tests/OpenCampusOrganizer
flutter build windows --release
flutter build apk --debug
```

ブラウザ版はサンプル専用です。

```powershell
flutter run -d chrome
```

- [使い方・環境設定](../../Docs/OpenCampusOrganizer/使い方.md)
- [Windowsインストーラー・署名付きAndroid APKの作成](../../Docs/OpenCampusOrganizer/配布.md)
- [構成・機能追加](../../Docs/OpenCampusOrganizer/設計.md)
- [検証範囲](../../Docs/OpenCampusOrganizer/検証.md)
