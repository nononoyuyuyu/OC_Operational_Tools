"""変更範囲と単調増加する配布バージョンからCIを計画する。"""
import json
import os
from pathlib import Path
import re
import subprocess

APP = "Source/OpenCampusOrganizer/"
VERSION_FILE = APP + "pubspec.yaml"
TARGETS = {"Windows": "windows-latest", "Android": "ubuntu-latest", "iOS": "macos-latest"}


def git(*args):
    return subprocess.check_output(["git", *args], text=True, encoding="utf-8").strip()


def parse_version(text):
    match = re.search(r"^version: ((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))\+([1-9]\d*)\s*$", text, re.M)
    if not match:
        raise ValueError("pubspec.yamlにはversion: X.Y.Z+ビルド番号を指定してください。")
    version, build = match.groups()
    if any(int(part) > 65535 for part in version.split(".")) or int(build) > 2100000000:
        raise ValueError("配布先OSのバージョン上限を超えています。")
    return version, int(build)


def validate_version(current, previous, app_changed, tags):
    if current == previous:
        if app_changed:
            raise ValueError("OCOのソース変更にはバージョンとビルド番号の増加が必要です。")
        return False
    version, build = current
    old_version, old_build = previous
    if tuple(map(int, version.split("."))) <= tuple(map(int, old_version.split("."))) or build <= old_build:
        raise ValueError("バージョンとビルド番号の両方を前の値より大きくしてください。")
    if f"v{version}" in tags:
        raise ValueError("同じバージョンのタグが既に存在します。重複公開はできません。")
    return True


def scope(paths):
    targets = set()
    test = False
    native_android = False
    for path in paths:
        if path.startswith((".github/", "Tests/OpenCampusOrganizer/ci_")):
            targets.update(TARGETS)
            test = native_android = True
        elif path.startswith(APP):
            relative = path[len(APP):]
            test = True
            if relative.startswith("android/"):
                targets.add("Android")
                native_android = True
            elif relative.startswith("windows/"):
                targets.add("Windows")
            elif relative.startswith("ios/"):
                targets.add("iOS")
            else:
                targets.update(TARGETS)
        elif path.startswith("Tests/OpenCampusOrganizer/"):
            test = True
            name = path.rsplit("/", 1)[-1]
            if "/android_appearance/" in path or name.startswith("android_"):
                targets.add("Android")
                native_android = True
            elif "/windows_appearance/" in path or name.startswith(("windows_", "icon_")):
                targets.add("Windows")
    return test, targets, native_android


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    kind = os.environ["GITHUB_EVENT_NAME"]
    sha = git("rev-parse", "HEAD")
    base = event["pull_request"]["base"]["sha"] if kind == "pull_request" else (event.get("before") or git("rev-parse", "HEAD^"))
    if not re.fullmatch(r"[0-9a-f]{40}", base) or base == "0" * 40:
        raise ValueError("比較元コミットを確認できません。")
    paths = git("diff", "--name-only", base, "HEAD").splitlines()
    current = parse_version(Path(VERSION_FILE).read_text(encoding="utf-8"))
    previous = parse_version(git("show", f"{base}:{VERSION_FILE}"))
    tags = git("tag", "--list", "v*").splitlines()
    # 同じmainコミットの再実行は配布物を上書きしない。公開前の失敗はpublish側で再開する。
    own_tag = f"v{current[0]}"
    already_tagged = kind != "pull_request" and own_tag in tags and git("rev-list", "-n", "1", own_tag) == sha
    effective_tags = [tag for tag in tags if not (already_tagged and tag == own_tag)]
    changed = any(path.startswith(APP) for path in paths)
    bumped = validate_version(current, previous, changed, effective_tags)
    version, build = current
    if bumped:
        notes = Path(f"Docs/OpenCampusOrganizer/releases/{version}.md")
        if not notes.is_file() or not notes.read_text(encoding="utf-8").strip():
            raise ValueError(f"配布内容を {notes.as_posix()} に記載してください。")
    for filename, needle in (
        (APP + "lib/app/app_shell.dart", f"バージョン {version}"),
        (APP + "lib/features/kakutei/data/discord_transport.dart", f", {version})"),
    ):
        if needle not in Path(filename).read_text(encoding="utf-8"):
            raise ValueError(f"表示バージョンが一致していません: {filename}")
    # バージョン文字列だけの同期を、共通機能の変更とは扱わない。
    version_paths = {VERSION_FILE, APP + "lib/app/app_shell.dart", APP + "lib/features/kakutei/data/discord_transport.dart"}
    relevant = []
    for path in paths:
        if bumped and path in version_paths:
            old = git("show", f"{base}:{path}").replace(f"{previous[0]}+{previous[1]}", "VERSION").replace(previous[0], "VERSION")
            new = Path(path).read_text(encoding="utf-8").strip().replace(f"{version}+{build}", "VERSION").replace(version, "VERSION")
            if old == new:
                continue
        relevant.append(path)
    test, targets, native_android = scope(relevant)
    release = kind != "pull_request" and os.environ["GITHUB_REF"] == "refs/heads/main" and bumped
    if release or kind == "workflow_dispatch":
        test = True
        targets.update(TARGETS)
    if bumped:
        test = True
    result = {
        "test": str(test).lower(), "build": str(bool(targets)).lower(),
        "native_android": str(native_android).lower(), "release": str(release).lower(),
        "web": str(kind == "workflow_dispatch").lower(),
        "benchmark": str(kind == "workflow_dispatch" or any("csv" in path.lower() for path in paths)).lower(),
        "version": version, "build_number": str(build),
        "matrix": json.dumps({"include": [{"target": t, "os": TARGETS[t]} for t in TARGETS if t in targets]}),
    }
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in result.items():
            output.write(f"{key}={value}\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
