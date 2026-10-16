#!/usr/bin/env python3
"""The Alpha and Stable release trains, as one script over `gh` (focus-h8jf).

Modelled on justspeaktoit's release-train.mjs, scaled to one surface: the direct Mac download
with a Sparkle feed per train. Every state the trains carry lives in GitHub releases, as a
manifest asset on an immutable tag, so a step can be re-run from any machine that holds `gh`:

    allocate      --source SHA [--rebuild]   cut alpha-build-N at a main commit (idempotent)
    configure     --tag TAG                  export the manifest as build settings ($GITHUB_ENV)
    status        --tag TAG                  is the mac-direct receipt on this tag `verified`?
    receipt       --tag TAG --status S --asset PATH...   record what was uploaded, with digests
    publish-alpha --tag TAG                  advance the alpha-latest pointer (never backwards)
    prepare       --alpha TAG --version V    freeze stable-candidate-N from a verified Alpha
    manifest-hash --tag TAG                  the SHA-256 the owner approves in Publish Stable
    publish       --tag CANDIDATE --approved-hash SHA256   publish vV from a frozen candidate
    withdraw      --tag CANDIDATE            record that a publication was withdrawn

Two rules the script keeps that a person could not be relied on to: a manifest is written once
and never edited (a rebuild is a new build number), and the Stable publisher refuses a candidate
whose manifest hash is not the one the owner typed.

It signs nothing and builds nothing. `release-mac.yml` does both, and calls this to read the
manifest before and to write the receipt after.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
PIPELINE = json.loads((ROOT / "Config" / "ReleasePipeline.json").read_text())
TRAINS = json.loads((ROOT / "Config" / "ReleaseTrains.json").read_text())
REPO = os.environ.get("RELEASE_REPOSITORY", PIPELINE["repository"])
MANIFEST_ASSET = "release-manifest.json"
SURFACE = "mac-direct"


# --- helpers ---------------------------------------------------------------------------------

def run(*args: str, check: bool = True, capture: bool = True, env: dict | None = None) -> str:
    result = subprocess.run(
        list(args), check=False, text=True,
        stdout=subprocess.PIPE if capture else None, stderr=subprocess.PIPE if capture else None,
        env={**os.environ, **(env or {})},
    )
    if check and result.returncode != 0:
        sys.stderr.write(result.stderr or "")
        raise SystemExit(f"FAIL {' '.join(args)} exited {result.returncode}")
    return (result.stdout or "").strip()


def gh(*args: str, check: bool = True) -> str:
    return run("gh", *args, "-R", REPO, check=check)


def gh_api(path: str, method: str = "GET", fields: dict | None = None) -> dict | list:
    args = ["gh", "api", f"repos/{REPO}/{path}", "-X", method]
    for key, value in (fields or {}).items():
        args += ["-f", f"{key}={value}"]
    return json.loads(run(*args))


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def release_exists(tag: str) -> bool:
    return subprocess.run(
        ["gh", "release", "view", tag, "-R", REPO], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0


def download_asset(tag: str, name: str, into: pathlib.Path) -> pathlib.Path | None:
    result = subprocess.run(
        ["gh", "release", "download", tag, "-R", REPO, "--pattern", name, "--dir", str(into), "--clobber"],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    target = into / name
    return target if result.returncode == 0 and target.exists() else None


def read_manifest(tag: str) -> dict:
    with tempfile.TemporaryDirectory() as scratch:
        path = download_asset(tag, MANIFEST_ASSET, pathlib.Path(scratch))
        if path is None:
            raise SystemExit(f"FAIL {tag} carries no {MANIFEST_ASSET}")
        return json.loads(path.read_text())


def manifest_bytes(manifest: dict) -> bytes:
    # Canonical: sorted keys, two-space indent, trailing newline. The hash the owner approves is
    # the hash of exactly these bytes, which is also what is uploaded.
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()


def upload(tag: str, *paths: pathlib.Path) -> None:
    gh("release", "upload", tag, *[str(p) for p in paths], "--clobber")


def write_output(key: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")
    print(f"{key}={value}")


def write_env(values: dict[str, str]) -> None:
    path = os.environ.get("GITHUB_ENV")
    for key, value in values.items():
        if path:
            with open(path, "a", encoding="utf-8") as handle:
                handle.write(f"{key}={value}\n")
        print(f"{key}={value}")


def next_number(prefix: str) -> int:
    refs = gh_api(f"git/matching-refs/tags/{prefix}")
    numbers = []
    for ref in refs:
        match = re.fullmatch(rf"refs/tags/{re.escape(prefix)}(\d+)", ref["ref"])
        if match:
            numbers.append(int(match.group(1)))
    return (max(numbers) + 1) if numbers else 1


def tags_for_source(prefix: str, source: str) -> list[str]:
    """Every tag with this prefix whose manifest names this source, newest first."""
    found = []
    for ref in gh_api(f"git/matching-refs/tags/{prefix}"):
        tag = ref["ref"].removeprefix("refs/tags/")
        if release_exists(tag):
            try:
                if read_manifest(tag)["source"] == source:
                    found.append(tag)
            except SystemExit:
                continue
    return sorted(found, key=lambda t: int(t.rsplit("-", 1)[-1]), reverse=True)


def create_tag(tag: str, source: str, message: str) -> None:
    run("git", "fetch", "origin", "--tags", "--quiet")
    if run("git", "tag", "-l", tag):
        existing = run("git", "rev-list", "-n", "1", tag)
        if existing != source:
            raise SystemExit(f"FAIL {tag} already exists at {existing}, not {source}")
        return
    run("git", "tag", "-a", tag, source, "-m", message)
    run("git", "push", "origin", f"refs/tags/{tag}")


def require_on_main(source: str) -> str:
    run("git", "fetch", "origin", "main", "--quiet")
    full = run("git", "rev-parse", "--verify", f"{source}^{{commit}}")
    if run("git", "merge-base", "--is-ancestor", full, "origin/main", check=False) != "" or \
            subprocess.run(["git", "merge-base", "--is-ancestor", full, "origin/main"]).returncode != 0:
        raise SystemExit(f"FAIL {source} is not on origin/main; a train is cut from main only")
    return full


# --- commands --------------------------------------------------------------------------------

def cmd_allocate(args: argparse.Namespace) -> None:
    source = require_on_main(args.source)
    prefix = PIPELINE["trains"]["alpha"]["buildTagPrefix"]
    existing = tags_for_source(prefix, source)
    if existing and not args.rebuild:
        print(f"note {source[:7]} already has {existing[0]}; allocation is idempotent")
        write_output("tag", existing[0])
        return
    number = next_number(prefix)
    tag = f"{prefix}{number}"
    manifest = {
        "tag": tag,
        "train": "alpha",
        "surface": SURFACE,
        "source": source,
        "version": PIPELINE["version"],
        "build": number,
        "minimumSystemVersion": PIPELINE["minimumSystemVersion"],
        "createdAt": now(),
        "rebuildOf": existing[0] if existing else None,
    }
    create_tag(tag, source, f"Alpha build {number} from {source[:7]}")
    with tempfile.TemporaryDirectory() as scratch:
        path = pathlib.Path(scratch) / MANIFEST_ASSET
        path.write_bytes(manifest_bytes(manifest))
        gh(
            "release", "create", tag, str(path), "--prerelease", "--verify-tag",
            "--title", f"Focus Sentinel Alpha build {number}",
            "--notes", f"Immutable Alpha build {number} from `{source}`. Assets arrive when the release worker verifies them; the Alpha feed moves only after that.",
        )
    write_output("tag", tag)


def cmd_configure(args: argparse.Namespace) -> None:
    manifest = read_manifest(args.tag)
    train = manifest["train"]
    row = TRAINS[train]
    write_env({
        "RELEASE_TAG": args.tag,
        "RELEASE_TRAIN": train,
        "RELEASE_VERSION": manifest["version"],
        "BUILD_NUMBER": str(manifest["build"]),
        "RELEASE_SOURCE": manifest["source"],
        "XCODE_CONFIGURATION": "Alpha" if train == "alpha" else "Release",
        "FEED_URL": row["feedURL"],
        "DOWNLOAD_TAG": (
            f"{PIPELINE['trains']['stable']['releaseTagPrefix']}{manifest['version']}"
            if train == "stable" else args.tag
        ),
        "MINIMUM_SYSTEM_VERSION": manifest["minimumSystemVersion"],
    })


def receipt_name() -> str:
    return f"receipt-{SURFACE}.json"


def cmd_status(args: argparse.Namespace) -> None:
    with tempfile.TemporaryDirectory() as scratch:
        path = download_asset(args.tag, receipt_name(), pathlib.Path(scratch))
        status = json.loads(path.read_text())["status"] if path else "missing"
    write_output("status", status)


def cmd_receipt(args: argparse.Namespace) -> None:
    assets = {}
    for asset in args.asset:
        path = pathlib.Path(asset)
        if not path.is_file():
            raise SystemExit(f"FAIL {asset} is not a file; a receipt names what was really uploaded")
        assets[path.name] = {"sha256": sha256(path), "bytes": path.stat().st_size}
    if args.status == "verified":
        if "appcast.xml" not in assets or not any(name.endswith(".dmg") for name in assets):
            raise SystemExit("FAIL a verified receipt requires an appcast and disk image")
        with tempfile.TemporaryDirectory() as scratch:
            for name, recorded in assets.items():
                if recorded["bytes"] == 0:
                    raise SystemExit(f"FAIL {name} is empty; no verified receipt written")
                remote = download_asset(args.tag, name, pathlib.Path(scratch))
                if remote is None or sha256(remote) != recorded["sha256"]:
                    raise SystemExit(f"FAIL {name} was not uploaded intact; no verified receipt written")
    receipt = {"surface": SURFACE, "status": args.status, "recordedAt": now(), "assets": assets}
    with tempfile.TemporaryDirectory() as scratch:
        path = pathlib.Path(scratch) / receipt_name()
        path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        upload(args.tag, path)
    print(f"ok   {args.tag} {receipt_name()} = {args.status} over {len(assets)} asset(s)")


def cmd_publish_alpha(args: argparse.Namespace) -> None:
    manifest = read_manifest(args.tag)
    if manifest["train"] != "alpha":
        raise SystemExit(f"FAIL {args.tag} is a {manifest['train']} manifest, not Alpha")
    pointer_tag = PIPELINE["trains"]["alpha"]["pointerTag"]
    with tempfile.TemporaryDirectory() as scratch_name:
        scratch = pathlib.Path(scratch_name)
        receipt = download_asset(args.tag, receipt_name(), scratch)
        if receipt is None or json.loads(receipt.read_text())["status"] != "verified":
            raise SystemExit(f"FAIL {args.tag} has no verified mac-direct receipt; the pointer moves only to verified assets")
        appcast = download_asset(args.tag, "appcast.xml", scratch)
        if appcast is None:
            raise SystemExit(f"FAIL {args.tag} carries no appcast.xml")
        # The pointer never moves backwards: a late build of an older number cannot roll it back.
        current = None
        if release_exists(pointer_tag):
            existing = download_asset(pointer_tag, "alpha-latest.json", scratch)
            if existing is not None:
                current = json.loads(existing.read_text())
                if current["build"] > manifest["build"]:
                    print(f"note alpha-latest is build {current['build']}; not moving it back to {manifest['build']}")
                    return
        pointer = {"tag": args.tag, "build": manifest["build"], "version": manifest["version"], "source": manifest["source"], "movedAt": now()}
        pointer_path = scratch / "alpha-latest.json"
        pointer_path.write_text(json.dumps(pointer, indent=2, sort_keys=True) + "\n")
        if not release_exists(pointer_tag):
            # A pointer release on the same commit as the first build it points at. Its tag is
            # moved by force on every advance; nothing else in the trains is ever moved.
            run("git", "fetch", "origin", "--tags", "--quiet")
            run("git", "tag", "-f", pointer_tag, manifest["source"])
            run("git", "push", "origin", f"refs/tags/{pointer_tag}", "--force")
            gh("release", "create", pointer_tag, "--prerelease", "--title", "Focus Sentinel Alpha (latest)",
               "--notes", "Pointer release: the Alpha Sparkle feed reads appcast.xml here. Assets are copies of the verified immutable build named in alpha-latest.json.")
        else:
            run("git", "fetch", "origin", "--tags", "--quiet")
            run("git", "tag", "-f", pointer_tag, manifest["source"])
            run("git", "push", "origin", f"refs/tags/{pointer_tag}", "--force")
        upload(pointer_tag, appcast, pointer_path)
    print(f"ok   {pointer_tag} -> {args.tag} (build {manifest['build']})")


def cmd_prepare(args: argparse.Namespace) -> None:
    alpha = read_manifest(args.alpha)
    if alpha["train"] != "alpha":
        raise SystemExit(f"FAIL {args.alpha} is not an Alpha manifest")
    with tempfile.TemporaryDirectory() as scratch:
        receipt = download_asset(args.alpha, receipt_name(), pathlib.Path(scratch))
        if receipt is None or json.loads(receipt.read_text())["status"] != "verified":
            raise SystemExit(f"FAIL {args.alpha} was never verified; Stable is prepared from a delivered Alpha only")
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        raise SystemExit(f"FAIL {args.version} is not a numeric X.Y.Z version")
    if release_exists(f"{PIPELINE['trains']['stable']['releaseTagPrefix']}{args.version}"):
        raise SystemExit(f"FAIL v{args.version} is already published")
    prefix = PIPELINE["trains"]["stable"]["candidateTagPrefix"]
    number = next_number(prefix)
    tag = f"{prefix}{number}"
    manifest = {
        "tag": tag,
        "train": "stable",
        "surface": SURFACE,
        "source": alpha["source"],
        "alphaTag": args.alpha,
        "version": args.version,
        "build": alpha["build"],
        "minimumSystemVersion": alpha["minimumSystemVersion"],
        "createdAt": now(),
    }
    create_tag(tag, alpha["source"], f"Stable candidate {number} from {args.alpha}")
    with tempfile.TemporaryDirectory() as scratch:
        path = pathlib.Path(scratch) / MANIFEST_ASSET
        path.write_bytes(manifest_bytes(manifest))
        gh(
            "release", "create", tag, str(path), "--draft", "--verify-tag",
            "--title", f"Focus Sentinel {args.version} candidate {number}",
            "--notes", f"Frozen from `{args.alpha}` at `{alpha['source']}`. Review the manifest, test the DMG, then approve its SHA-256 in Publish Stable.",
        )
    print(f"manifest sha256: {hashlib.sha256(manifest_bytes(manifest)).hexdigest()}")
    write_output("tag", tag)


def cmd_manifest_hash(args: argparse.Namespace) -> None:
    manifest = read_manifest(args.tag)
    write_output("sha256", hashlib.sha256(manifest_bytes(manifest)).hexdigest())


def cmd_publish(args: argparse.Namespace) -> None:
    manifest = read_manifest(args.tag)
    if manifest["train"] != "stable":
        raise SystemExit(f"FAIL {args.tag} is not a Stable candidate")
    actual = hashlib.sha256(manifest_bytes(manifest)).hexdigest()
    if actual != args.approved_hash.lower():
        raise SystemExit(f"FAIL the approved hash does not match {args.tag}'s manifest ({actual}); nothing published")
    release_tag = f"{PIPELINE['trains']['stable']['releaseTagPrefix']}{manifest['version']}"
    with tempfile.TemporaryDirectory() as scratch_name:
        scratch = pathlib.Path(scratch_name)
        receipt_path = download_asset(args.tag, receipt_name(), scratch)
        if receipt_path is None:
            raise SystemExit(f"FAIL {args.tag} has no mac-direct receipt")
        receipt = json.loads(receipt_path.read_text())
        if receipt["status"] != "verified":
            raise SystemExit(f"FAIL {args.tag} receipt is {receipt['status']}, not verified")
        published: list[pathlib.Path] = []
        for name, recorded in receipt["assets"].items():
            path = download_asset(args.tag, name, scratch)
            if path is None:
                raise SystemExit(f"FAIL {args.tag} no longer carries {name}")
            if sha256(path) != recorded["sha256"]:
                raise SystemExit(f"FAIL {name} on {args.tag} does not match its receipt digest; nothing published")
            published.append(path)
        run("git", "fetch", "origin", "--tags", "--quiet")
        create_tag(release_tag, manifest["source"], f"Focus Sentinel {manifest['version']}")
        if not release_exists(release_tag):
            gh("release", "create", release_tag, "--verify-tag", "--latest",
               "--title", f"Focus Sentinel {manifest['version']}",
               "--notes", f"Published from `{args.tag}` (Alpha `{manifest['alphaTag']}`, build {manifest['build']}) at `{manifest['source']}`.")
        upload(release_tag, *published)
        gh("release", "edit", release_tag, "--draft=false", "--latest")
        publication = {"publishedAs": release_tag, "approvedHash": actual, "publishedAt": now(), "assets": receipt["assets"]}
        publication_path = scratch / "publication.json"
        publication_path.write_text(json.dumps(publication, indent=2, sort_keys=True) + "\n")
        upload(args.tag, publication_path)
    print(f"ok   {release_tag} published from {args.tag}")


def cmd_withdraw(args: argparse.Namespace) -> None:
    with tempfile.TemporaryDirectory() as scratch:
        path = pathlib.Path(scratch) / "withdrawn.json"
        path.write_text(json.dumps({"withdrawnAt": now(), "reason": args.reason}, indent=2) + "\n")
        upload(args.tag, path)
    print(f"ok   {args.tag} marked withdrawn")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("allocate"); p.add_argument("--source", required=True); p.add_argument("--rebuild", action="store_true"); p.set_defaults(run=cmd_allocate)
    p = sub.add_parser("configure"); p.add_argument("--tag", required=True); p.set_defaults(run=cmd_configure)
    p = sub.add_parser("status"); p.add_argument("--tag", required=True); p.set_defaults(run=cmd_status)
    p = sub.add_parser("receipt"); p.add_argument("--tag", required=True); p.add_argument("--status", required=True, choices=["verified", "failed"]); p.add_argument("--asset", action="append", default=[]); p.set_defaults(run=cmd_receipt)
    p = sub.add_parser("publish-alpha"); p.add_argument("--tag", required=True); p.set_defaults(run=cmd_publish_alpha)
    p = sub.add_parser("prepare"); p.add_argument("--alpha", required=True); p.add_argument("--version", required=True); p.set_defaults(run=cmd_prepare)
    p = sub.add_parser("manifest-hash"); p.add_argument("--tag", required=True); p.set_defaults(run=cmd_manifest_hash)
    p = sub.add_parser("publish"); p.add_argument("--tag", required=True); p.add_argument("--approved-hash", required=True); p.set_defaults(run=cmd_publish)
    p = sub.add_parser("withdraw"); p.add_argument("--tag", required=True); p.add_argument("--reason", default="publication failed"); p.set_defaults(run=cmd_withdraw)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
