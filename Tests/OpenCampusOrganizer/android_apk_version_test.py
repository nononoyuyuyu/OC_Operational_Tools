"""生成したCPU別APKの実マニフェストとABIを検証する。"""
import os
import pathlib
import re
import subprocess

app = pathlib.Path(__file__).resolve().parents[2] / "Source" / "OpenCampusOrganizer"
match = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)\s*$", (app / "pubspec.yaml").read_text(), re.M)
assert match, "pubspec.yamlのバージョンが不正です"
sdk = pathlib.Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ["ANDROID_HOME"])
versions = [p for p in (sdk / "build-tools").iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", p.name)]
aapt = max(versions, key=lambda p: tuple(map(int, p.name.split(".")))) / ("aapt.exe" if os.name == "nt" else "aapt")
for abi in ("armeabi-v7a", "arm64-v8a", "x86_64"):
    apk = app / "build/app/outputs/flutter-apk" / f"app-{abi}-debug.apk"
    badging = subprocess.check_output([str(aapt), "dump", "badging", str(apk)], text=True, encoding="utf-8")
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    assert package and package.groups() == ("jp.nononoyuyuyu.open_campus_organizer", match[2], match[1]), apk.name
    assert re.search(r"^native-code: '" + re.escape(abi) + r"'\s*$", badging, re.M), apk.name
    print(f"PASS {apk.name}: versionName={match[1]}, versionCode={match[2]}, ABI={abi}")
