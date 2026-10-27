#!/usr/bin/env python3
"""Assemble the companion release from verified binaries and a clean git HEAD.

No builds, installation, signing, driver changes or upload are performed.
"""
import argparse
import hashlib
import plistlib
from pathlib import Path
import shutil
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parents[1]
LABEL = "Shuttle-Video-0.1.54-Player-0.3.2"
MAIN_SHA256 = "5465dab9dc7346917bd19f8100ae8c340164d427cfff208bf001b1c125b41124"


def digest(path):
    with path.open("rb") as stream:
        h = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
        return h.hexdigest()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main-installer", type=Path, required=True)
    parser.add_argument("--player-release", type=Path, required=True,
                        help="Verified unpacked Shuttle-Player-0.3.2 folder")
    parser.add_argument("--player-zip", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True,
                        help="New, non-existing output folder outside the checkout")
    args = parser.parse_args()
    pkg, player, player_zip, out = (p.resolve() for p in
        (args.main_installer, args.player_release, args.player_zip, args.out))
    require(not out.exists(), "Refusing to overwrite an existing release folder")
    require(ROOT not in out.parents, "Output must be outside the source checkout")
    require(not run("git", "status", "--porcelain"), "Commit source changes first")
    require(digest(pkg) == MAIN_SHA256, "Main installer differs from original 0.1.54")
    commit = run("git", "rev-parse", "HEAD")
    for line in (player / "SHA256SUMS.txt").read_text().splitlines():
        expected, name = line.split("  ", 1)
        path = (player / name).resolve()
        require(player in path.parents, "Invalid Player manifest path")
        require(digest(path) == expected, f"Player manifest mismatch: {name}")
    for path in (player / "Source").rglob("*"):
        if path.is_file():
            other = ROOT / "player" / path.relative_to(player / "Source")
            require(other.is_file() and digest(other) == digest(path),
                    f"Repository differs from tested Player source: {other}")
    with zipfile.ZipFile(player_zip) as archive:
        require(archive.testzip() is None, "Damaged Player ZIP")
        for path in player.rglob("*"):
            if path.is_file():
                name = "Shuttle-Player-0.3.2/" + path.relative_to(player).as_posix()
                require(hashlib.sha256(archive.read(name)).hexdigest() == digest(path),
                        f"Player ZIP differs from verified folder: {name}")
    app = player / "Shuttle Player.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info["CFBundleShortVersionString"] == "0.3.2", "Wrong Player version")
    require(info["CFBundleVersion"] == "7", "Wrong Player build")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

    out.mkdir(parents=True)
    source_zip = out / (LABEL + "-Source.zip")
    subprocess.run(["git", "archive", "--format=zip", "--prefix=" + LABEL + "-Source/",
                    "--output=" + str(source_zip), commit], cwd=ROOT, check=True)
    shutil.copy2(pkg, out / "Shuttle-Video-0.1.54.pkg")
    shutil.copy2(player_zip, out / "Shuttle-Player-0.3.2.zip")
    complete = out / (LABEL + "-Complete")
    complete.mkdir()
    shutil.copy2(pkg, complete / "Shuttle-Video-0.1.54.pkg")
    shutil.copy2(source_zip, complete / source_zip.name)
    shutil.copytree(app, complete / app.name)
    shutil.copytree(ROOT / "docs", complete / "docs")
    (complete / "player").mkdir()
    for name in ("README.md", "Read Me.html", "COPYING", "THIRD-PARTY-NOTICES.md",
                 "VALIDATION.md", "CHANGELOG.md"):
        shutil.copy2(ROOT / "player" / name, complete / "player" / name)
    shutil.copytree(ROOT / "player/docs", complete / "player/docs")
    for name in ("README.md", "COPYING", "THIRD-PARTY-NOTICES.md", "RELEASING.md",
                 "Publisher checklist.md", "BUILD-VALIDATION.md"):
        shutil.copy2(ROOT / name, complete / name)
    shutil.copy2(player / "Player-Output-Test.mov", complete / "Player-Output-Test.mov")
    (complete / "Install.txt").write_text(
        "Shuttle Video 0.1.54 + Shuttle Player 0.3.2\n\n"
        "Read README.md and docs/Whats-New-Player-0.3.2.md first.\n"
        "First installation: read the main security guide, close capture/editor/Shuttle "
        "apps and install Shuttle-Video-0.1.54.pkg. Copy Shuttle Player.app to Applications "
        "separately. Existing main 0.1.54 users only need to replace Player while closed.\n"
        "Main package and drivers are unchanged. Player is not installed by the package.\n"
        "Player: File > Open Video URL; choose Download first or Stream. Stream supports "
        "scrub and ten-second skips; Loop uses Download first. Stretch is the default.\n"
        "Unsigned installer; ad-hoc apps, not notarized. Main extensions require the "
        "documented SIP development setup. No security settings are changed automatically. "
        "Intel/older macOS runtime and the new Stream seek HDMI workflow remain unqualified.\n"
        "Exact corresponding repository source is in the included Source ZIP. Extract it "
        "to build/change either app; licences and pinned helper inputs are included.\n")
    (complete / "RELEASE-COMMIT.txt").write_text(commit + "\n")
    files = sorted(p for p in complete.rglob("*") if p.is_file())
    (complete / "SHA256SUMS.txt").write_text("".join(
        f"{digest(p)}  {p.relative_to(complete).as_posix()}\n" for p in files))
    complete_zip = out / (LABEL + "-Complete.zip")
    with zipfile.ZipFile(complete_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(complete.rglob("*")):
            require(not path.is_symlink(), "ZIP writer requires ordinary files")
            if path.is_file():
                archive.write(path, complete.name + "/" + path.relative_to(complete).as_posix())
    for archive_path in (source_zip, complete_zip):
        with zipfile.ZipFile(archive_path) as archive:
            require(archive.testzip() is None, f"ZIP integrity error: {archive_path}")
    assets = sorted(p for p in out.iterdir() if p.is_file())
    (out / "SHA256.txt").write_text("".join(f"{digest(p)}  {p.name}\n" for p in assets))
    print(f"Prepared {out}\nSource commit: {commit}\nNothing installed or published.")


if __name__ == "__main__":
    main()
