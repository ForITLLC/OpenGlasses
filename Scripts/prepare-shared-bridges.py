#!/usr/bin/env python3
"""Prepare package-free mark/Controls inputs from the published Common Git objects.

FORIT_COMMON_ROOT must name an existing official repository containing the release
tag and be frozen at that exact release; this script never fetches, checks out,
or modifies that repository. Its official exporter bytes must match Git objects.
Target membership and actual compiler/resource closure still need native proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REPOSITORY = "https://github.com/ForITLLC/for-iCommon.git"
VERSION = "0.31.5"
REVISION = "d6f69ba013783b0aab33a8233af4a5331dd9ddc1"
TAG_OBJECT = "4a7b35a75c9384f8cabb7271185c86a43b0363e4"
EXPORTERS = {
    "Mark": ("Scripts/brand-export.py", "083db68e0e7f37ae1cc1394146e177fa7d42162d1b7f3b11005c436f23fc3701", "manifest.json",
             {"ForITMark.swift", "ForITMarkBridgePalette.swift", "forit-hex.png"}),
    "Controls": ("Scripts/controls-export.py", "441eb924e8e9fd32bd8e308e7002fa41e85493d49b7e5bec0db512125344a0ce", "controls-manifest.json",
                 {"ForITBrand.swift", "ForITControlMetrics.swift", "ForITControls.swift"}),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def ordinary_path(path):
    path = Path(os.path.abspath(path))
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        raise ValueError(f"symlink path is not supported: {path}")
    return path


def prepare(source, output):
    source, output = ordinary_path(source), ordinary_path(output)
    app_root = Path(__file__).resolve().parent.parent
    app_build = app_root / ".build" / "forit-bridges"
    if ((output == app_root or app_root in output.parents)
            and not app_build in output.parents):
        raise ValueError("in-repository bridge output must be below .build/forit-bridges")
    if output == source or source in output.parents:
        raise ValueError("bridge output cannot modify the Common source repository")

    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args])

    origin = git("config", "--local", "--null", "--get-all", "remote.origin.url")
    if origin not in {REPOSITORY.encode() + b"\0", b"git@github.com:ForITLLC/for-iCommon.git\0"}:
        raise ValueError("FORIT_COMMON_ROOT must have the official Common origin")
    tag = "refs/tags/" + VERSION
    if (git("cat-file", "-t", tag).strip() != b"tag"
            or git("rev-parse", tag).decode().strip() != TAG_OBJECT
            or git("rev-parse", tag + "^{commit}").decode().strip() != REVISION):
        raise ValueError("Common annotated release tag differs from the pinned published release")
    if git("rev-parse", "HEAD").decode().strip() != REVISION:
        raise ValueError("FORIT_COMMON_ROOT must be frozen at the pinned published release")

    # Validate both official working-tree programs against their pinned Git objects before execution.
    for name, (path, expected, _, _) in EXPORTERS.items():
        canonical = git("show", REVISION + ":" + path)
        if digest(canonical) != expected or ordinary_path(source / path).read_bytes() != canonical:
            raise ValueError("official exporter hash differs: " + path)

    output.mkdir(parents=True, exist_ok=True)
    bindings = {}
    for name, (path, exporter_hash, manifest_name, expected_outputs) in EXPORTERS.items():
        generated = ordinary_path(output / name)
        allowed = expected_outputs | {manifest_name}
        if name == "Mark":
            allowed.add("mark-auth-manifest.json")
        if generated.exists() and {p.name for p in generated.iterdir()} - allowed:
            raise ValueError("unexpected bridge output; use a clean derived directory: " + str(generated))
        command = [sys.executable, "-I", "-B", str(source / path), "--source", str(source),
                   "--revision", REVISION, "--output", str(generated)]
        if name == "Mark":
            command += ["--version", VERSION]
        subprocess.run(command, check=True)
        manifest_file = ordinary_path(generated / manifest_name)
        manifest = json.loads(manifest_file.read_text())
        if (manifest["repository"] != REPOSITORY or manifest["revision"] != REVISION
                or set(manifest["outputs"]) != expected_outputs):
            raise ValueError("export manifest is not bound to the expected Common release")
        for filename, expected_hash in manifest["outputs"].items():
            if digest(ordinary_path(generated / filename).read_bytes()) != expected_hash:
                raise ValueError("exported output hash differs: " + filename)
        for filename, expected_hash in manifest["inputs"].items():
            if digest(git("show", REVISION + ":" + filename)) != expected_hash:
                raise ValueError("exported input hash differs: " + filename)
        if name == "Mark" and manifest.get("compilationCondition") != "FORIT_MARK_BRIDGE":
            raise ValueError("mark compilation condition differs")
        bindings[name] = {"exporter": path, "exporterSHA256": exporter_hash,
                          "manifest": name + "/" + manifest_name,
                          "manifestSHA256": digest(manifest_file.read_bytes()),
                          "outputs": manifest["outputs"]}
        if name == "Mark":
            auth_file = ordinary_path(generated / "mark-auth-manifest.json")
            auth = json.loads(auth_file.read_text())
            expected_auth = {"schema": "forit.mark-bridge-auth.v1", "version": VERSION,
                             "exporter": {"path": path, "sha256": exporter_hash}, **manifest}
            if auth != expected_auth:
                raise ValueError("mark authentication manifest differs from the published export")
            bindings[name]["authenticationManifest"] = "Mark/mark-auth-manifest.json"
            bindings[name]["authenticationManifestSHA256"] = digest(auth_file.read_bytes())
    binding = {"repository": REPOSITORY, "version": VERSION, "revision": REVISION,
               "annotatedTagObject": TAG_OBJECT, "bridges": bindings}
    ordinary_path(output / "bridge-manifest.json").write_text(json.dumps(binding, indent=2) + "\n")
    print(f"Prepared shared bridges at {REVISION}: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=os.environ.get("FORIT_COMMON_ROOT"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.source is None or args.output is None:
        parser.error("set FORIT_COMMON_ROOT or supply --source")
    try:
        prepare(args.source, args.output)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Shared bridge preparation failed: {error}\n")
