"""配布ペイロード内の秘密情報・個人プロファイルパスを値を表示せず検査する。"""
from pathlib import Path
import re
import sys
import zipfile

PATTERNS = [
    rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    rb"https://(?:discord(?:app)?\.com)/api/webhooks/\d+/[A-Za-z0-9_-]{30,}",
    rb"(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}",
    rb"mfa\.[A-Za-z0-9_-]{30,}",
    rb"[A-Za-z]:[/\\]Users[/\\](?!runneradmin[/\\]|runner[/\\]|Public[/\\]|Default[/\\])[^/\\\s\x00<>]+[/\\]",
    rb"/(?:Users|home)/(?!runner/|runneradmin/|Public/|Default/)[A-Za-z0-9_.-]+/",
]


def inspect(data, name):
    for content in (data, data.replace(b"\x00", b"")):
        if any(re.search(pattern, content, re.I) for pattern in PATTERNS):
            raise ValueError(f"配布物に秘密情報または個人パスの候補があります: {name}（値は非表示）")
    if Path(name).suffix.lower() in {".jks", ".keystore", ".dpapi", ".p12", ".pfx"}:
        raise ValueError(f"署名用ファイルを配布できません: {name}")


def audit(path):
    if path.is_dir():
        for file in path.rglob("*"):
            if file.is_file():
                inspect(file.read_bytes(), file.name)
    elif path.suffix == ".apk":
        with zipfile.ZipFile(path) as apk:
            for entry in apk.infolist():
                if not entry.is_dir():
                    inspect(apk.read(entry), entry.filename)
    else:
        inspect(path.read_bytes(), path.name)


if __name__ == "__main__":
    for value in sys.argv[1:]:
        audit(Path(value))
    print("配布ペイロード検査: PASS")
