# 3か月連続空欄ツールの検証

Node.js 18以降、外部パッケージ不要。テストの氏名と識別子は架空値。

```bash
node --test Tests/OC_ThreeMonthBlankHighlighter/*.test.js
```

`logic.test.js`: 日付、任意位置ヘッダー、登録翌月から先月の月数、当月記入による除外、空欄、登録日保留、日付重複、処理上限。4,096通りの月別記入パターンと欠落月込み729通りを独立オラクルで照合する。

`workflow.test.js`: 読取り→確認→ロック→再読取→専用書式更新。利用者の3例、当月の未来日への記入、月替わり、版混在、対象外への復帰、元色と他ルールの保持、該当0件、冪等性、保護・結合、競合、復元失敗を確認。

`safety.test.js`: 構文、グローバル宣言、最小権限、禁止API、固定数式。今回変更なし。

`helpers.js`はGASソースをそのままNode VMで読み込む。GASサービスを模擬しているため、ブラウザ画面やGoogle側での実行を証明するものではない。

必須CIは既存の`Tests/OC_KakuteiExtractor/three-month-integration.test.js`から全テストを取り込み、既存GASと同じVMでの結合読込も確認する。新ツールの単独実行と同時にこの入口も維持する。
