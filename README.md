# OC_tools

オープンキャンパス業務で使用するツールのソースコードとドキュメントを管理するリポジトリです。

## ツール一覧

### Open Campus Organizer（OCO）

Windows・Android・iOSを対象とするFlutterアプリです。ツール一覧、操作履歴、設定の共通画面を備え、最初の機能としてDiscordの投稿者抽出・ロール付与・一括解除・CSV出力を行う「確定ロール」を実装しています。初期配色はダークで、白・青、ウォームグレー、セージグリーン、アプリコットにも切り替えられます。

スマートフォンでは名前と処理予定のスクロール一覧を使い、本文確認とCSV出力を省いています。PCでは投稿の詳細表示とCSV出力を利用できます。

処理内容と進捗を端末に保存し、通信の復帰時や次回起動時に未完了の処理を再開します。Windowsは任意のタスクトレイ常駐、Androidは進捗通知付きのバックグラウンド処理、iOSはOSが許可する時間内の継続処理に対応します。Windowsの導入・削除時には、設定と履歴の引き継ぎ・削除を選べます。

- [使い方・ビルド方法](Docs/OpenCampusOrganizer/使い方.md)
- [インストーラー・APKの配布と作成](Docs/OpenCampusOrganizer/配布.md)
- [最新版のダウンロード](https://github.com/nononoyuyuyu/OC_tools/releases/latest)
- [構成と機能追加](Docs/OpenCampusOrganizer/設計.md)
- [機能対応表と検証範囲](Docs/OpenCampusOrganizer/検証.md)
- [UI調査と設計判断](Docs/OpenCampusOrganizer/UI再設計.md)
- [ソースコード](Source/OpenCampusOrganizer/)
- [テスト](Tests/OpenCampusOrganizer/)

### OC_KakuteiExtractor

Google スプレッドシートの`学生情報一覧`から、`学籍番号`、`名前`、`フリガナ`、`SA/TA`と指定期間の日付列を抽出し、フリガナ昇順の書式なしTSVとしてクリップボードへコピーするGASツールです。

通常フィルタがある場合は、フィルタ本体とフィルタ範囲を残したまま、各列の絞り込み条件だけを解除します。手動で非表示にされた行は再表示します。行グループは展開・折りたたみを行わず、既存の開閉状態を保持します。抽出対象は行グループの開閉状態に依存しません。

- [設計書](Docs/OC_KakuteiExtractor/設計書.md)
- [使い方・導入方法](Docs/OC_KakuteiExtractor/使い方%26導入方法.md)
- [保守について](Docs/OC_KakuteiExtractor/保守について.md)
- [フィルタ解除・行再表示仕様](Docs/OC_KakuteiExtractor/フィルタ解除・行再表示仕様.md)
- [フリガナ許容文字仕様](Docs/OC_KakuteiExtractor/フリガナ許容文字仕様.md)
- [識別子正規化・エラー診断仕様](Docs/OC_KakuteiExtractor/識別子正規化仕様.md)
- [トラブルシューティング](Docs/OC_KakuteiExtractor/トラブルシューティング.md)
- [ソースコード](Source/OC_KakuteiExtractor/)
- [テスト](Tests/OC_KakuteiExtractor/)

## リポジトリ構成

```text
Docs/ツール名/...
Source/ツール名/...
Tests/ツール名/...
```

## 更新ルール

- 変更はブランチ上で行い、PRを作成します。
- コミットメッセージ、PRタイトル、PR本文は日本語で記載します。
- 本プロジェクトで新規作成・更新するドキュメントは日本語で記載します。
