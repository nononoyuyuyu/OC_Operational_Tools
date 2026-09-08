#!/usr/bin/env bash
# ビルドだけでは検出できない、起動元alias無効化による画面終了を検証する。
set -euo pipefail
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export ANDROID_AVD_HOME="$RUNNER_TEMP/oco-avd"
mkdir -p "$ANDROID_AVD_HOME"
sdkmanager 'emulator' 'system-images;android-35;google_apis;x86_64' >/dev/null
printf 'no\n' | avdmanager create avd --name oco-ci --path "$ANDROID_AVD_HOME/oco-ci.avd" --package 'system-images;android-35;google_apis;x86_64' --force >/dev/null
sudo chmod a+rw /dev/kvm
df -h "$ANDROID_AVD_HOME"
"$ANDROID_HOME/emulator/emulator" -avd oco-ci -port 5554 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -partition-size 2048 -memory 2048 -cores 2 >"$RUNNER_TEMP/oco-emulator.log" 2>&1 &
emulator_pid=$!
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then cat "$RUNNER_TEMP/oco-emulator.log"; fi
  timeout 10 adb -s emulator-5554 emu kill >/dev/null 2>&1 || true
  kill "$emulator_pid" 2>/dev/null || true
  wait "$emulator_pid" || true
  exit "$status"
}
trap cleanup EXIT
ready=false
for attempt in {1..150}; do
  kill -0 "$emulator_pid"
  if [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)" = 1 ]; then ready=true; break; fi
  sleep 2
done
test "$ready" = true
adb -s emulator-5554 shell input keyevent 82
cd android
./gradlew :app:connectedDebugAndroidTest --console=plain
