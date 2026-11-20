#!/bin/bash
# The Mini Apple launcher runs this compile-only check for the standalone Watch target.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
SOURCE=$(git rev-parse HEAD)
if [ "$SOURCE" != "${FORIT_SOURCE_COMMIT:-}" ]; then
  echo "Watch Release check requires the Apple launcher's exact source commit" >&2
  exit 2
fi
if [ -e DoloresWatch/Secrets.plist ] || [ -L DoloresWatch/Secrets.plist ]; then
  echo "The compile-only check does not take a Watch credentials file" >&2
  exit 2
fi

OUT="$ROOT/build/watch-release-$(date -u +%Y%m%dT%H%M%SZ)"
DD="$ROOT/build/dd-watch-release"
mkdir -p "$OUT"
COMMON_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/openglasses-watch-common.XXXXXXXX")
trap 'rm -rf -- "$COMMON_TEMP"' EXIT
COMMON_TEMP=$(cd "$COMMON_TEMP" && pwd -P)
export FORIT_COMMON_ROOT="$COMMON_TEMP/for-iCommon"
EXPORTER="$ROOT/Scripts/prepare-shared-bridges.py"
COMMON_REVISION=$(python3 -I -B -c 'import runpy,sys; print(runpy.run_path(sys.argv[1])["REVISION"])' "$EXPORTER")

# The existing exporter authenticates the official origin, annotated tag, verifier
# bytes and canonical output. Generate both declared bridge groups before XcodeGen.
if ! GIT_TERMINAL_PROMPT=0 git clone -q --no-checkout https://github.com/ForITLLC/for-iCommon.git \
    "$FORIT_COMMON_ROOT" > /dev/null 2>&1; then
  echo "Official Common checkout failed using the Mini's existing Git access" >&2
  exit 1
fi
git -C "$FORIT_COMMON_ROOT" checkout -q --detach "$COMMON_REVISION"
for target in DoloresWatch GlassesActivityWidget; do
  python3 -I -B "$EXPORTER" --source "$FORIT_COMMON_ROOT" \
    --output "$ROOT/.build/forit-bridges/$target"
done
xcodegen generate > "$OUT/xcodegen.log" 2>&1 || {
  tail -30 "$OUT/xcodegen.log" >&2
  exit 1
}

LOCK="$ROOT/OpenGlasses.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
cp "$LOCK" "$OUT/Package.resolved.log"
RC=0
xcodebuild build -jobs 2 -project OpenGlasses.xcodeproj -scheme DoloresWatch -configuration Release \
  -sdk watchos -destination 'generic/platform=watchOS' -derivedDataPath "$DD" \
  -clonedSourcePackagesDirPath "$ROOT/build/watch-release-packages" -scmProvider system \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  FORIT_COMMON_ROOT="$FORIT_COMMON_ROOT" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  > "$OUT/watch-release.log" 2>&1 || RC=$?

PROOF_RC=0
python3 -I -B - "$ROOT" "$DD" "$OUT" "$LOCK" "$SOURCE" "$RC" <<'PY_WATCH_PROOF' || PROOF_RC=$?
import hashlib
import json
import plistlib
import sys
from pathlib import Path

root, dd, out, lock = map(Path, sys.argv[1:5])
source, build_exit = sys.argv[5], int(sys.argv[6])
bridges = root / ".build/forit-bridges/DoloresWatch"
binding = (bridges / "bridge-manifest.json").read_bytes()
(out / "bridge-manifest.json.log").write_bytes(binding)
frozen_lock = (out / "Package.resolved.log").read_bytes()
log = out / "watch-release.log"
digest = lambda data: hashlib.sha256(data).hexdigest()
receipt = {
    "source": source,
    "target": "DoloresWatch",
    "configuration": "Release",
    "sdk": "watchos",
    "signingAllowed": False,
    "buildExit": build_exit,
    "packageResolutionSHA256": digest(frozen_lock),
    "bridgeManifestSHA256": digest(binding),
    "bridgeRelease": json.loads(binding)["version"],
    "compilerLogSHA256": digest(log.read_bytes()),
    "compilerMembership": [],
}
if build_exit == 0:
    try:
        if lock.read_bytes() != frozen_lock:
            raise ValueError("Xcode changed the committed package resolution")
        app = dd / "Build/Products/Release-watchos/DoloresWatch.app"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if (info.get("CFBundleIdentifier") != "com.forit.openglasses.dolores.watchkitapp"
                or info.get("CFBundleSupportedPlatforms") != ["WatchOS"]
                or not (app / info["CFBundleExecutable"]).is_file()
                or (app / "Secrets.plist").exists()):
            raise ValueError("The built bundle has the wrong identity, platform, executable, or resources")
        bridge_entries = json.loads(binding)["bridges"]
        expected = {
            str(bridges / group / name): sha
            for group, value in bridge_entries.items()
            for name, sha in value["outputs"].items()
            if name.endswith(".swift")
        }
        membership_root = dd / "Build/Intermediates.noindex/OpenGlasses.build/Release-watchos/DoloresWatch.build"
        inputs = sorted(membership_root.glob("Objects-normal/*/DoloresWatch.SwiftFileList"))
        if not inputs:
            raise ValueError("The Watch Release compiler source lists are missing")
        for path in inputs:
            raw = path.read_bytes()
            files = set(raw.decode().splitlines())
            if not set(expected) <= files:
                raise ValueError("The Watch Release compiler source list is missing a canonical bridge input")
            if any(digest(Path(name).read_bytes()) != sha for name, sha in expected.items()):
                raise ValueError("A Watch compiler input differs from the authenticated bridge manifest")
            name = "DoloresWatch-" + path.parent.name + ".SwiftFileList.log"
            (out / name).write_bytes(raw)
            receipt["compilerMembership"].append({
                "architecture": path.parent.name,
                "sourceListSHA256": digest(raw),
                "canonicalInputs": sorted(str(Path(p).relative_to(root)) for p in expected),
            })
        receipt["bundleIdentifier"] = info["CFBundleIdentifier"]
    except (ValueError, OSError, KeyError) as error:
        receipt["proofError"] = str(error)
(out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
if "proofError" in receipt:
    sys.exit(receipt["proofError"])
PY_WATCH_PROOF

(cd "$OUT" && /usr/bin/zip -q evidence.zip -- ./*.log receipt.json)
if [ "$RC" -ne 0 ]; then
  tail -35 "$OUT/watch-release.log" >&2
  exit "$RC"
fi
[ "$PROOF_RC" -eq 0 ] || exit "$PROOF_RC"
echo "Watch Release compiled and canonical source membership verified. Receipt: $OUT/receipt.json"
