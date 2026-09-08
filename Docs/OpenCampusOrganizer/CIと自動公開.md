# CIと自動公開

## PRとmainの役割

PRは変更箇所に応じて検証します。文書だけの変更はFlutterや各OSのビルドを省略します。Android・Windows・iOS固有の変更は該当OSをビルドし、Dart共通コード・依存関係・CI基盤の変更は全OSを検証します。表示名とUser-Agentのバージョン文字列だけの同期は、共通機能の変更とは扱いません。

mainで新しい配布バージョンを検出すると、全OSをビルドします。Windowsの検証済みインストーラーと、既存の配布鍵で署名・検証したAndroid APKを同じワークフローのRelease公開ジョブへ渡します。公開のために別途ローカルでビルドし直す必要はありません。iOSは署名なしのシミュレータービルドまでで、IPAは公開しません。

PRの検証はマージ前の不具合を止め、mainの検証は実際に配布するコミットと成果物を確認します。この2段階は維持します。GASは短時間で終わる独立したテストを継続します。

必須チェックは `OCO検証` と `GASの単体・統合・安全性テスト` です。`OCO検証` は計画・必要なテスト・必要なビルドが成功した場合だけ成功します。必要なジョブの失敗・取消・予期しない省略はマージを止めます。

## バージョンの更新

配布に影響する `Source/OpenCampusOrganizer/` 内の変更には、以下を必須とします。

1. `pubspec.yaml` の `version: X.Y.Z+ビルド番号` を更新する。バージョンとビルド番号の両方をmainの値より大きくする。
2. 設定画面とDiscordのUser-Agentにあるバージョンも合わせる。不一致はCIで失敗する。
3. `Docs/OpenCampusOrganizer/releases/X.Y.Z.md` に日本語のRelease本文を追加する。

例: `0.4.3+12` → `0.4.4+13`。`0.4.3+13`、`0.4.4+12`、減少、既存タグと同じ版は拒否します。文書・テストだけの変更には配布番号の更新を要求せず、Releaseも作成しません。

## 署名と公開権限

GitHubの `release` 環境はmainブランチからのみ利用できます。`OCO_ANDROID_KEYSTORE_BASE64` と `OCO_ANDROID_STORE_PASSWORD` を環境Secretとして保管します。PR・forkでは署名鍵を使いません。ローカルの既存鍵を変更・削除する必要はありません。

鍵はAndroidの署名ステップ中に一時ディレクトリへ復元し、終了時に削除します。配布済みの証明書SHA-256と一致しないAPK、Debug APK、異なるID・バージョン・ABIは公開しません。Windowsの展開前ペイロードとAPK内容について、秘密情報や個人プロファイルパスの代表的なパターンも検査します。このパターン検査はすべての個人情報や機密情報を保証するものではなく、新しい外部サービスや設定ファイルを追加する際には別途確認が必要です。

通常のジョブは読み取り権限です。Release公開ジョブだけに `contents: write` と成果物取得用の `actions: read` を与えます。mainへの直接push・強制push・削除は禁止を維持し、別途の常設PATは使用しません。

## 公開失敗と再実行

公開ジョブはmainのコミットを対象にdraftを作り、インストーラー1個・APK4個・SHA256SUMS.txtを添付します。GitHubから取得し直して全ファイルのSHA-256を照合した後に公開し、公開後も再取得して確認します。

失敗した場合はActionsの失敗ジョブを確認し、同じ実行の失敗ジョブのみ再実行してください。同じコミット・同じ添付ファイルのdraftであれば不足分の公開処理を再開できます。公開済みReleaseやハッシュの異なる添付は上書きしません。別コミットへのタグの移動、古い版を最新へ戻す操作も拒否します。ビルドをやり直して成果物が変わる場合は新しいバージョンを使ってください。

GitHub仕様: [環境とブランチ制限](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)、[ジョブごとの権限](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)。
