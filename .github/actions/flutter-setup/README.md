# Flutter準備用Action

既存のFlutter準備処理を維持しながら、内部のキャッシュActionもコミットで固定するために取り込んだものです。

- 取得元: https://github.com/subosito/flutter-action/tree/1a449444c387b1966244ae4d4f8c696479add0b2
- 対象: `action.yaml`、`setup.sh`、`LICENSE`
- 変更: `action.yaml`内の2つの`actions/cache@v5`を`actions/cache@caa296126883cff596d87d8935842f9db880ef25`へ固定。
- `setup.sh`と`LICENSE`は取得元と同一です。第三者の著作権表示・ライセンスを保持します。
- 更新時は本体と内部Actionの差分を確認し、依存先を含めて完全なコミットSHAで固定してください。

取り込み前のSHA-256:

- `action.yaml`: `5c0e5a243d010be58a41bded0cbca71687317b712d6876ebf6ab434494adcb75`
- `setup.sh`: `35f0cd9e9c1d7a643448223573b4a03879e63676fdc27872de3d0104d5bf89f9`
- `LICENSE`: `329009b59300a124af69c29c9ad19d38079207d9098c76fe0b51dc79a76a2e9a`
