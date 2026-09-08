"""このmain実行の検証済み成果物だけを公開し、公開前後に全添付を照合する。"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
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


def find_release(repository, tag):
    # タグ名のRESTエンドポイントは公開前のdraftを返さない。
    release = api_optional(f"repos/{repository}/releases/tags/{tag}")
    if release is not None:
        return release
    pages = json.loads(gh("api", "--paginate", "--slurp", f"repos/{repository}/releases?per_page=100"))
    matches = [release for page in pages for release in page if release["tag_name"] == tag]
    if len(matches) > 1:
        raise ValueError("同じタグのReleaseが複数あります。公開処理を停止します。")
    return matches[0] if matches else None


def expected_names(version):
    return {f"OpenCampusOrganizer-{version}-{suffix}" for suffix in [
        "windows-x64-setup.exe", "android.apk", "android-arm64-v8a.apk",
        "android-armeabi-v7a.apk", "android-x86_64.apk",
    ]}


def collect_assets(download, destination, version):
    paths = list(download.rglob("*"))
    if any(path.is_symlink() for path in paths):
        raise ValueError("配布物にシンボリックリンクは使用できません。")
    files = [path for path in paths if path.is_file()]
    expected = expected_names(version)
    if len(files) != len(expected) or {path.name for path in files} != expected:
        raise ValueError("配布ファイルはインストーラー1個と署名済みAPK4個だけである必要があります。")
    destination.mkdir(parents=True, exist_ok=True)
    # upload-artifactが保持するバージョンディレクトリを取り除き、公開名を一意にする。
    for path in files:
        shutil.copyfile(path, destination / path.name)


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
    download = Path("dist")
    dist = Path(tempfile.mkdtemp(prefix="oco-release-stage-", dir=os.environ["RUNNER_TEMP"]))
    expected = expected_names(version)
    collect_assets(download, dist, version)
    for path in dist.iterdir():
        audit(path)
    checksums = "".join(f"{sha256(dist / name)}  {name}\n" for name in sorted(expected))
    (dist / "SHA256SUMS.txt").write_text(checksums, encoding="utf-8", newline="\n")
    hashes = {p.name: sha256(p) for p in dist.iterdir()}
    marker = f"<!-- oco-source: {sha} -->"
    notes = Path(f"Docs/OpenCampusOrganizer/releases/{version}.md").read_text(encoding="utf-8")
    notes += f"\n\n対象コミット: `{sha}`\n\n{marker}\n"
    release = find_release(repository, tag)
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
        # 作成直後は検索結果への反映が遅れるため、POSTの応答をそのまま使う。
        payload = Path(os.environ["RUNNER_TEMP"]) / "oco-release-create.json"
        payload.write_text(json.dumps({"tag_name": tag, "target_commitish": sha,
                                      "name": f"Open Campus Organizer {version}",
                                      "body": notes, "draft": True}, ensure_ascii=False), encoding="utf-8")
        release = json.loads(gh("api", "--method", "POST", f"repos/{repository}/releases", "--input", str(payload)))
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
    published = find_release(repository, tag)
    ref = api_optional(f"repos/{repository}/git/ref/tags/{tag}")
    if not published or published["draft"] or published["prerelease"] or not ref or ref["object"]["sha"] != sha:
        raise ValueError("公開状態またはタグのコミットが一致しません。")
    print(f"公開・添付6個のSHA-256照合完了: {published['html_url']}")


if __name__ == "__main__":
    main()
