#!/usr/bin/env bash
set -euo pipefail
folder="$RUNNER_TEMP/oco-actionlint"
mkdir -p "$folder"
curl --fail --location --silent --show-error --proto '=https' \
  https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
  --output "$folder/actionlint.tar.gz"
printf '%s  %s\n' '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' "$folder/actionlint.tar.gz" | sha256sum --check
tar -xzf "$folder/actionlint.tar.gz" -C "$folder" actionlint
"$folder/actionlint" -shellcheck='' -pyflakes=''
