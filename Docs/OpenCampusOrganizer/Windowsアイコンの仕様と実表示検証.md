# Windowsアイコンの仕様と実表示検証

2026-09-23にMicrosoftのWin32仕様とChromiumの実装を再調査した。対象はInno Setupで配布する、MSIXではないWindows版OCO。調査履歴は [再発調査](Windowsアイコン再発調査-20260922.md) を参照する。

## 表示先を区別する

| 表示先 | 主な情報源・更新手段 | 確認上の限界 |
| --- | --- | --- |
| ウィンドウ、Alt+Tab | `WM_SETICON` の大小アイコン | この成功だけではタスクバーやスタートを検証できない |
| 実行中のタスクバーグループ | AppUserModelID、対応ショートカット、ウィンドウの再起動情報 | 同じIDのグループが表示済み画像を保持する場合がある |
| タスクバーの既存ピン留め | ピン留めされたリンクと補助リンク | スタート用の元リンクだけの変更では不足する場合がある |
| スタートの既存ピン留め・すべてのアプリ | Shellが登録・保持しているアプリ項目 | 新しいピン留めやAppsFolderの画像取得と、既存表示の再描画は別に検証する |

[WM_SETICONの仕様](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-seticon) はウィンドウの大小アイコンを扱う。[AppUserModelIDの仕様](https://learn.microsoft.com/en-us/windows/win32/shell/appids) は、同じアプリのプロセス・ウィンドウ・ショートカットでIDを揃えること、プロセスIDをUIの表示前に設定すること、ウィンドウIDがプロセスIDを上書きすることを定めている。

## ショートカットとウィンドウの再起動情報

Microsoftは、起動用ショートカットがある場合には、そのAppUserModelIDとアイコン・起動情報を利用する構成を推奨している。ウィンドウの `RelaunchIconResource` は、明示的なウィンドウIDと再起動情報を使う場合の仕組みであり、すべての表示先を直接変更するAPIではない。[再起動アイコンの仕様](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-relaunchiconresource)

OCOは既存リンクとウィンドウの両方に再起動アイコンを保存してきた。両方を使う限り、同じ不変ICOを指すように揃えた後で通知する。起動用リンクのないポータブル起動もあるため、再起動情報を一律に除去する変更は行わない。同じIDを空にして戻す操作は、画像の無効化として扱わない。

既存ピン留めの検索には `TaskBar` に加えて `FOLDERID_ImplicitAppShortcuts` を含める。このKnown FolderはMicrosoftが定義しており、Chromiumもグループごとの下位フォルダーにあるリンクを更新対象にしている。OCOは1階層下までに制限し、起動先が実行中EXEと一致する既存リンクだけを更新する。リンクの新設やピン留めの変更は行わない。[Known Folderの定義](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid)、[Chromiumの実装](https://github.com/chromium/chromium/blob/main/chrome/browser/profiles/profile_shortcut_manager_win.cc)

## 通知の意味

- `SHUpdateImage` には変更前の画像の場所・番号・画像リストの番号を渡す。新しいICO名を作っただけでは、旧画像の無効化にならない。[SHUpdateImage](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shupdateimagew)
- `SHCNE_UPDATEITEM` は既存項目の変更を通知する。PIDLを使うときはデスクトップからの絶対PIDLを渡す。
- `SHCNE_ASSOCCHANGED` は広範なShellキャッシュに影響し、他のアイコンの再描画も起こし得る。Windows 11向けのChromium実装でも、この通知だけではタスクバーが更新されないとして、対象リンクの通知を続けている。
- `SHCNF_FLUSH` が保証するのは通知の配送完了である。スタートやタスクバーの最終描画完了を保証するものではない。[SHChangeNotify](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shchangenotify)

したがって、通知関数の呼出し、画像APIの正しい戻り値、自動テストの合格だけから、実表示の修正完了とは判断しない。実際には起きていない削除・再作成イベントを送ったり、Windowsの内部データベースを直接編集したりしない。

## まず、検証している実行ファイルを照合する

0.4.7公開後の調査では、修正候補0.4.8をビルドした後も実際に起動していたのは0.4.7だった。診断用に一度だけ送った通知による変化を、その後のテーマ切替にも適用される修正と混同した。この状態では候補版の有効性を判断できない。

実表示テストの前に、ビルドしたEXEと起動中EXEを照合する。

```powershell
pwsh -File Source/OpenCampusOrganizer/tool/verify_windows_theme_runtime.ps1 `
  -ExpectedExecutable Source/OpenCampusOrganizer/build/windows/x64/runner/Release/open_campus_organizer.exe
```

この読み取り専用スクリプトは、PID・起動日時・バージョン・EXEのSHA-256を記録し、不一致なら失敗する。設定、資格情報、操作履歴は読み取らない。成功しても `shellDisplayVerified` はfalseのままにし、画面を見た証拠に置き換えない。

## 配布前の受け入れ条件

1. 候補版のコミット、インストーラーのSHA-256、Windowsのビルド、起動中EXEの照合結果を残す。
2. 稼働中の業務処理がある環境では正常終了と更新のタイミングを利用者と調整する。設定・履歴を保持し、テスト目的のDiscord操作は行わない。
3. 同じ既存ショートカット・同じ既存ピン留めで、ダーク→白・青→ウォームグレー→セージ→アプリコット→ダークを3周する。
4. 各回のアプリ内配色、実行中タスクバー、スタートの既存ピン留め、すべてのアプリを個別に記録する。一度だけ成功した結果を連続切替の成功にしない。
5. 同色の再試行、正常終了・再起動、旧版からの更新で保存色が戻ることを確認する。新しくピン留めし直した結果は既存ピン留めの結果と分ける。
6. 操作前のテーマへ戻す。未確認の表示先や再現している症状があれば、Draftと記録に残し「修正済み」として公開しない。

Windows全体のアイコンキャッシュ削除、Explorerやスタートの強制再起動、自動的なピン留め解除・再作成は、この受け入れテストにも製品の更新処理にも含めない。
