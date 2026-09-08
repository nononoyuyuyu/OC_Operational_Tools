"""main専用環境の既存署名鍵でAPKを作成し、検証済みのものだけを保存する。"""
import base64
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

SIGNER = "067f21d198dacdbea0f618e89a09a1b61ac7bccfe0917604daced28222ac12e2"
APP_ID = "jp.nononoyuyuyu.open_campus_organizer"


def main():
    if os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
        raise ValueError("配布署名はmainだけで実行できます。")
    encoded = os.environ.pop("OCO_ANDROID_KEYSTORE_BASE64", "")
    if not encoded or not os.environ.get("OCO_ANDROID_STORE_PASSWORD"):
        raise ValueError("release環境のAndroid署名設定がありません。")
    version, build = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)\s*$", Path("pubspec.yaml").read_text(), re.M).groups()
    sdk = Path(os.environ["ANDROID_HOME"])
    tool = max((sdk / "build-tools").iterdir(), key=lambda p: tuple(map(int, p.name.split("."))) if re.fullmatch(r"\d+\.\d+\.\d+", p.name) else (0,))
    destination = Path("../../artifacts/android-release")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="oco-signing-", dir=os.environ["RUNNER_TEMP"]) as temporary:
        key = Path(temporary) / "release.jks"
        key.write_bytes(base64.b64decode(encoded, validate=True))
        key.chmod(0o600)
        del encoded
        os.environ["OCO_ANDROID_STORE_FILE"] = str(key)
        try:
            for split in (False, True):
                subprocess.run(["flutter", "build", "apk", "--release", "--no-pub", *(["--split-per-abi"] if split else [])], check=True)
                for abi in (["armeabi-v7a", "arm64-v8a", "x86_64"] if split else [None]):
                    source = Path("build/app/outputs/flutter-apk") / (f"app-{abi}-release.apk" if abi else "app-release.apk")
                    signature = subprocess.check_output([str(tool / "apksigner"), "verify", "--print-certs", str(source)], text=True)
                    if f"Signer #1 certificate SHA-256 digest: {SIGNER}" not in signature:
                        raise ValueError("APKの署名が既存の配布鍵と一致しません。")
                    badging = subprocess.check_output([str(tool / "aapt"), "dump", "badging", str(source)], text=True)
                    if f"package: name='{APP_ID}' versionCode='{build}' versionName='{version}'" not in badging or "application-debuggable" in badging:
                        raise ValueError("APKのID・配布番号・Debug属性が不正です。")
                    if "application-label:'OC'" not in badging:
                        raise ValueError("Androidの表示名がOCではありません。")
                    expected = {abi} if abi else {"armeabi-v7a", "arm64-v8a", "x86_64"}
                    line = re.search(r"^native-code: (.+)$", badging, re.M)
                    if not line or set(re.findall(r"'([^']+)'", line[1])) != expected:
                        raise ValueError("APKのCPU構成が不正です。")
                    suffix = f"android-{abi}.apk" if abi else "android.apk"
                    shutil.copyfile(source, destination / f"OpenCampusOrganizer-{version}-{suffix}")
        finally:
            os.environ.pop("OCO_ANDROID_STORE_FILE", None)
            os.environ.pop("OCO_ANDROID_STORE_PASSWORD", None)


if __name__ == "__main__":
    main()
