"""このmain実行の検証済み成果物だけを公開し、公開前後に全添付を照合する。"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from audit_payload import audit


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True, encoding="utf-8")


def api_optional(endpoint):
    result = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True, encoding="utf-8")
    if result.returncode == 0:
        return json.loads(result.stdout)
    if "(HTTP 404)" in result.stderr:
        return None
    raise RuntimeError("GitHub APIの取得に失敗しました。公開処理を停止します。")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_names(version):
    return {f"OpenCampusOrganizer-{version}-{suffix}" for suffix in [
        "windows-x64-setup.exe", "android.apk", "android-arm64-v8a.apk",
        "android-armeabi-v7a.apk", "android-x86_64.apk",
    ]}


def verify_download(tag, hashes):
    with tempfile.TemporaryDirectory(prefix="oco-download-") as folder:
        gh("release", "download", tag, "--dir", folder)
        actual = {file.name: sha256(file) for file in Path(folder).iterdir() if file.is_file()}
        if actual != hashes:
            raise ValueError("Releaseの添付ファイルがビルド成果物と一致しません。")


def main():
    if os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
        raise ValueError("Releaseはmainだけで公開できます。")
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    version = re.search(r"^version: (\d+\.\d+\.\d+)\+\d+\s*$", Path("Source/OpenCampusOrganizer/pubspec.yaml").read_text(), re.M)[1]
    tag = f"v{version}"
    dist = Path("dist")
    expected = expected_names(version)
    if {p.name for p in dist.iterdir()} != expected:
        raise ValueError("配布ファイルはインストーラー1個と署名済みAPK4個だけである必要があります。")
    for path in dist.iterdir():
        audit(path)
    checksums = "".join(f"{sha256(dist / name)}  {name}\n" for name in sorted(expected))
    (dist / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8", newline="\n")
    hashes = {p.name: sha256(p) for p in dist.iterdir()}
    marker = f"<!-- oco-source: {sha} -->"
    notes = Path(f"Docs/OpenCampusOrganizer/releases/{version}.md").read_text(encoding="utf-8")
    notes += f"\n\n対象コミット: `{sha}`\n\n{marker}\n"
    notes_file = Path(os.environ["RUNNER_TEMP"]) / "oco-release-notes.md"
    notes_file.write_text(notes, encoding="utf-8")
    endpoint = f"repos/{repository}/releases/tags/{tag}"
    release = api_optional(endpoint)
    existing_ref = api_optional(f"repos/{repository}/git/ref/tags/{tag}")
    if existing_ref and (existing_ref["object"]["type"] != "commit" or existing_ref["object"]["sha"] != sha):
        raise ValueError("タグが別のコミットまたは既存の注釈付きタグを参照しています。変更しません。")
    latest = api_optional(f"repos/{repository}/releases/latest")
    if latest and latest["tag_name"] != tag:
        latest_version = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", latest["tag_name"])
        if latest_version and tuple(map(int, latest_version.groups())) >= tuple(map(int, version.split("."))):
            raise ValueError("より新しいReleaseが公開済みです。古い版を最新に戻すことはできません。")
    if release:
        if marker not in (release["body"] or "") or release["target_commitish"] != sha:
            raise ValueError("同じバージョンは別のコミットで使用済みです。")
        if not release["draft"]:
            verify_download(tag, hashes)
            print(f"{tag} は同じ成果物で公開済みです。変更しません。")
            return
    else:
        # --clobberは使わない。途中の失敗は同じコミット・同じ成果物のdraftだけ再開する。
        gh("release", "create", tag, "--draft", "--target", sha, "--title", f"Open Campus Organizer {version}", "--notes-file", str(notes_file))
        release = api_optional(endpoint)
    existing = {asset["name"]: asset for asset in release["assets"]}
    if set(existing) - set(hashes):
        raise ValueError("draftに想定外の添付ファイルがあります。")
    for name, digest in hashes.items():
        if name in existing:
            if existing[name].get("digest") != f"sha256:{digest}":
                raise ValueError("draftの添付ファイルが異なります。上書きしません。")
        else:
            gh("release", "upload", tag, str(dist / name))
    verify_download(tag, hashes)
    gh("release", "edit", tag, "--draft=false", "--latest")
    verify_download(tag, hashes)
    published = api_optional(endpoint)
    ref = api_optional(f"repos/{repository}/git/ref/tags/{tag}")
    if not published or published["draft"] or published["prerelease"] or not ref or ref["object"]["sha"] != sha:
        raise ValueError("公開状態またはタグのコミットが一致しません。")
    print(f"公開・添付6個のSHA-256照合完了: {published['html_url']}")


if __name__ == "__main__":
    main()
