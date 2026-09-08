#!/usr/bin/env bash
# ビルドだけでは検出できない、起動元alias無効化による画面終了を検証する。
set -euo pipefail
sdkmanager 'system-images;android-35;google_apis;x86_64' >/dev/null
printf 'no\n' | avdmanager create avd --name oco-ci --package 'system-images;android-35;google_apis;x86_64' --force >/dev/null
sudo chmod a+rw /dev/kvm
"$ANDROID_HOME/emulator/emulator" -avd oco-ci -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect >"$RUNNER_TEMP/oco-emulator.log" 2>&1 &
emulator_pid=$!
trap 'adb -s emulator-5554 emu kill >/dev/null 2>&1 || true; wait "$emulator_pid" || true' EXIT
timeout 180 adb -s emulator-5554 wait-for-device
ready=false
for attempt in {1..90}; do
  if [ "$(adb -s emulator-5554 shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; then ready=true; break; fi
  sleep 2
done
test "$ready" = true
adb -s emulator-5554 shell input keyevent 82
cd android
./gradlew :app:connectedDebugAndroidTest --console=plain
