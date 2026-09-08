# Open Campus Organizerのテスト

リポジトリ規約に合わせて、テストをアプリ本体とは別の `Tests/OpenCampusOrganizer` に配置しています。

`Source/OpenCampusOrganizer` で実行します。

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib tool ../../Tests/OpenCampusOrganizer
flutter analyze --no-pub
flutter test --no-pub ../../Tests/OpenCampusOrganizer --reporter expanded
```

| ファイル | 主な検証対象 |
| --- | --- |
| `domain_test.dart` | 日本時間、権限上書き、保護ロール、投稿の境界・重複・Bot除外・最小投稿数、全ページ取得、条件変更、取消、通信失敗、操作記録、CSV、クラッシュ復元 |
| `transport_test.dart` | 429待機、直列化、待機中取消、接続の変更、更新の不確実性、機密情報を表示しないエラー、ApplicationのIntent |
| `discord_api_test.dart` | REST投稿の任意member、authorの必須検証、不正な型の拒否、投稿抽出後のメンバー照合 |
| `controller_widget_test.dart` | 条件変更後の実行禁止、二重実行防止、切断、PC・スマートフォンの画面と文字拡大 |
| `confirmation_test.dart` | 一括解除の確認操作、保存領域の分離、添付のみの投稿 |
| `operation_feedback_test.dart` | 解除対象0人・URLコピーの共通通知、全配色、直前の入力エラーの解消、クリック時の表示、長文のスクロールと通知更新時の位置 |
| `mobile_feedback_test.dart` | スマホ通知の6秒消去、同文の再通知、画面移動、他の操作を妨げないこと、中止、長文エラー、読み上げ時の保持、入力エラーの解消 |
| `mobile_layout_test.dart` | Android・iOSの小画面、一覧内スクロール、50人への到達、回転と位置保持、文字拡大、キーボード、本文・CSVの省略、全配色の接続状態・通知・システムバー |
| `history_results_test.dart` | 保存結果の展開、少人数時の高さ、50人を重複なくページ送り、成否の余白、開閉・スクロールのキー分離 |
| `history_layout_test.dart` | 履歴一覧・詳細のレスポンシブ表示とページ位置の保持、文字拡大、長い失敗理由、通知欄との位置関係、非表示詳細を読まないこと、65履歴を重複なく取得 |
| `history_storage_test.dart` | 1,000履歴のページ読込、詳細1件取得、旧schema移行、派生索引の再生成、破損末尾、追記失敗、終了記録の復元、CSV保存の選択、実ファイルの送信前flush |
| `operation_rows_test.dart` | 不変スナップショット、葉の境界をまたぐランダム更新、件数集計と変更行、範囲外・変更操作の拒否 |
| `extraction_retention_test.dart` | 投稿の非保持、最小投稿数未満の照会省略、件数・Bot・上限の維持、旧再開条件の互換性 |
| `android_apk_version_test.py` | 実際のCPU別Debug APKのapplicationId・versionName・versionCode・ABI |
| `appearance_history_test.dart` | 5色の保存・復元、初期ダークと旧設定の継続、連続選択、文字・状態表示・入力枠のコントラスト、共通履歴、設定変更時の入力保持 |
| `window_appearance_test.dart` | Windowsへ初期配色と全5色を通知、モバイルでの分離、アイコン更新失敗時にも配色を保存 |
| `branding_migration_test.dart` | 旧Windows保存先からの移行、旧ファイル・新設定の保持、失敗時の再試行、削除後のTokenの再取り込み防止。資格情報は架空の値で検証 |
| `performance_test.dart` | メンバーの一括照合と個別照会への切替、ページ上限、権限の再確認、403での停止 |
| `performance_benchmark_test.dart` | 架空の50人による実際のHTTPアダプターの要求回数比較。時間計測と実Discord接続は行わない |
| `support.dart` | 通信と保存のテスト用実装 |
| `workspace_layout_test.dart` | 通知による位置ずれ、画面に応じた件数、局所スクロールに切り替わる高さでの対象者保持、大小画面のタブ、ページ送り・検索・投稿詳細 |
| `saved_settings_test.dart` | 保存済みTokenでの選択値・入力値復元、Bot・サーバー・サンプルの分離、削除済み対象、破損設定 |
| `extraction_time_test.dart` | 同じ開始・終了分のUI入力、秒・端数とAPI取得境界、空欄の終了日時、年・日付・うるう日の境界 |
| `windows_installer_test.ps1` | 専用ディレクトリへの導入・再導入、全配布ファイルのハッシュ一致、登録の削除、ユーザー作成ファイルの保持。既存のインストールを検出した場合は実行しない |
| `windows_userdata_test.ps1` | 検証用保存先を組み込んだ専用インストーラーで、設定・履歴・架空資格情報の引き継ぎ、初期化、削除、旧版再取り込み防止、リンク先の保持を確認 |
| `recovery_test.dart` | 応答を失った更新の再照合、再起動時の続き、承認対象・Botの一致、取消、保存停止、終了済み履歴と破損記録、固定期間での再抽出 |
| `runtime_test.dart` | 初期設定と復元、前面・抽出・複数タスク・自動終了オフの条件、終了確認と保存待ち、OS時間切れと通知の中止 |

テストは実Bot Tokenを使用せず、Discordサーバーを書き換えません。実際のToken保存・共有メニュー・Discord権限は、各環境で別途確認する必要があります。

Windowsインストーラーの検証は、OCOをインストールしていないWindowsユーザーで、リポジトリのルートから実行します。アプリは自動起動しません。ログと検証用ファイルは `artifacts/installer-test-*` に残します。VC++ランタイムが不足している環境では、インストーラーがその導入も行います。

```powershell
pwsh -File Tests/OpenCampusOrganizer/windows_installer_test.ps1 -Installer artifacts/release/0.4.0/OpenCampusOrganizer-0.4.0-windows-x64-setup.exe
```

設定・履歴の削除テストは、実際のユーザー領域へ触れない専用ビルドで行います。専用ファイル名とビルド時の保存先・SHA-256を記録した `userdata-test.json` が一致しなければテストを拒否します。

```powershell
$testData = Join-Path (Get-Location) 'artifacts/userdata-check'
$testInstaller = Join-Path (Get-Location) 'artifacts/userdata-check-installer'
pwsh -File Source/OpenCampusOrganizer/tool/build_windows_installer.ps1 -UserDataTestRoot $testData -OutputDirectory $testInstaller
pwsh -File Tests/OpenCampusOrganizer/windows_userdata_test.ps1 -Installer (Join-Path $testInstaller 'OpenCampusOrganizer-userdata-test-setup.exe')
```

CIはFlutterの解析・テスト、Windowsインストーラーの作成と導入・再導入・削除、CPU別Android Debug APKの生成と実マニフェストの確認、iOSシミュレーター向けビルドを行います。Androidの配布鍵はCIに渡していません。署名付きAPKの作成・検証方法は [配布手順](../../Docs/OpenCampusOrganizer/配布.md) を参照してください。

実LocalStoreとスナップショットのベンチマークは [0.4.1の性能検証](../../Docs/OpenCampusOrganizer/履歴と抽出の性能改善-0.4.1.md) を参照してください。架空のデータを新しい測定用ディレクトリに作成し、実ユーザーの保存先は使いません。

既存のGASテストについて、作業開始時点の `main`（`3b88e198cc3073db9a6971c9d233e8fc43022af2`）では `workflow.test.js:273` と `static.test.js:42` が確認メッセージの文言不一致で失敗します。同じSHAの独立した作業ディレクトリで再現済みです。この追加ではGASのソースとテストを変更していません。
