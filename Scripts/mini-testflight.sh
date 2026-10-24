#!/bin/bash
# Usage: Scripts/mini-testflight.sh [--no-upload | --matrix-pr <number>]
#
# Unit tests, archive, export and upload of ForIT Glasses (OpenGlasses, com.forit.openglasses.dolores) to internal
# TestFlight, run by hand on the Mac mini over ssh. It replaces .github/workflows/build-and-upload.yml: under the ForIT
# checklist (CI-1, CI-3) the checks and the upload run on the Mini, never on GitHub-hosted macOS. Ported from
# for-Notes apps/ios/Scripts/mini-testflight.sh (ForITLLC/for-Notes f77e50a3); Scripts/asc_resolve.py and
# Scripts/asc_attach.py are adapted copies from the same commit. The profile script is ForITCommon's (checklist CI-4).
#
# Run it from a copy of the repo on the Mini (rsync the worktree there first):
#   ssh mini-lan 'cd <copy> && Scripts/mini-testflight.sh'              tests, archive, export, upload, wait for VALID
#   ssh mini-lan 'cd <copy> && Scripts/mini-testflight.sh --no-upload'  stops once the signed IPA is exported and checked
#   Scripts/mini-testflight.sh --matrix-pr <number>                  tests and full PR matrix only; capture GO required
# Run the full PR matrix once on the merge-ready tree. Upload requires its retained identity receipt and tested app,
# then reuses those exact images without another test, simulator boot or matrix. Keep the PR commit's Git object
# through a squash merge so both commits can be verified to have the same tree. Nothing here grants capture GO.
# Each step prints "step <name> rc=<rc> <seconds>s"; its log is build/testflight-<UTC time>/<name>.log.
#
# 1. OpenGlasses/Secrets.plist: DOLORES_API_KEY from the environment, written as the workflow wrote it. With no key
#    the plist holds an empty dict and the app asks each person for their own key at onboarding. The key is never
#    printed.
# 2. In --matrix-pr mode: xcodegen, then unit tests (scheme OpenGlasses, -only-testing:OpenGlassesTests) on its own
#    iPhone simulator, through the Mini's route /Users/Shared/ci-sim/ci-sim-lane.sh --lane OpenGlasses (checklist
#    CI-2): the iPhone ci-sim-lanes.conf gives the lane, else ci-OpenGlasses-iPhone, which the route creates and
#    primes once. Since 2026-10-11 a lane may not use another lane's simulator or one that belongs to no lane. The
#    shared gate run boots it through the boot slot and refuses a test run on any other simulator. Tests and the
#    device matrix share that boot; --run-end releases the run's simulators on success and failure (CI-2).
#    A red test stops the run before anything is signed (CI-1).
# 3. App Store Connect (Scripts/asc_resolve.py, read-only): the app record (must be 6761319043), its internal group
#    "ForIT Internal", and the build number: the highest build number App Store Connect has for the app, plus one,
#    the rule the workflow used.
#    Upload runs the current conformance gate and requires the full PR proof before signing or archiving. Captures
#    keep the tested simulator app's actual identity; the intended upload build is recorded separately. The full PR
#    grid has 68 actual PNGs (own iPhone and three iPad layouts, including AX5) and 34 SE/Max gap rows; its 24 standard
#    light/dark iPhone/iPad cells are the upload's VS-1 subset. Mac/Vision/Watch distribution stays uncovered.
# 4. Signing, the for-Notes way (the login keychain is locked over ssh, and Xcode's automatic signing would want an
#    Apple Development identity the Mini does not have). ForITCommon's Scripts/asc/asc_provision.py (checklist CI-4),
#    from the package the tests resolved into build/spm (the version project.yml pins), makes or reuses the two App
#    Store profiles project.yml names in each target's Release configuration, chosen by the certificate's public key:
#      com.forit.openglasses.dolores                  "OpenGlasses App Store"         OpenGlasses.app
#      com.forit.openglasses.dolores.activity-widget  "OpenGlasses Widget App Store"  PlugIns/GlassesActivityWidget.appex
#    DoloresWatch is not embedded in the app and is not built. The team's Apple Distribution identity,
#    ~/AppleCerts/distribution.{key,der}, goes into a throwaway keychain with a random password, first in the search
#    list for the run and deleted on exit. The archive (Release, generic/platform=iOS) overrides project.yml on the
#    command line with CODE_SIGN_STYLE=Manual and that identity, as the workflow did, and pins codesign to the
#    throwaway keychain. No profile is named on the command line: that setting would reach the Swift packages too.
# 5. Export, checked before anything leaves the Mini; then (without --no-upload) the upload, and
#    Scripts/asc_attach.py waits up to 20 minutes for the build to be VALID, answers export compliance as the workflow
#    did, and confirms the build reaches "ForIT Internal". TestFlight internal testing only: the upload sets
#    testFlightInternalTestingOnly, and nothing here makes an external group or a public link or submits anything
#    for review (docs/access-control.md).
#
# Env (defaults are the team's): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, CERT_DIR, DOLORES_API_KEY, WHATS_NEW (the
# build's What to Test text; none by default), BETA_GROUP_NAME.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export PATH=/opt/homebrew/bin:$PATH  # xcodegen and python3 with PyJWT; a non-login ssh shell does not have them

USAGE="usage: Scripts/mini-testflight.sh [--no-upload | --matrix-pr <number>]"
UPLOAD=1 MATRIX_PR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-upload) UPLOAD=""; shift ;;
    --matrix-pr)
      [ $# -ge 2 ] && [[ $2 =~ ^[1-9][0-9]*$ ]] || { echo "$USAGE" >&2; exit 2; }
      MATRIX_PR=$2 UPLOAD=""; shift 2 ;;
    -h | --help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done

# Establish source identity before writing secrets, logs or generated project files. A copied tree
# without its real Git metadata, a dirty checkout, or hidden tracked changes cannot name a build.
SOURCE_ORIGIN=$(git remote get-url origin) || { echo "no genuine Git origin"; exit 1; }
case "$SOURCE_ORIGIN" in
  https://github.com/ForITLLC/OpenGlasses | https://github.com/ForITLLC/OpenGlasses.git | \
  git@github.com:ForITLLC/OpenGlasses.git | ssh://git@github.com/ForITLLC/OpenGlasses.git) ;;
  *) echo "origin must be exactly ForITLLC/OpenGlasses on github.com"; exit 1 ;;
esac
[ "$(git rev-parse --show-toplevel)" = "$PWD" ] || { echo "run from the genuine repository root"; exit 1; }
SOURCE_SHA=$(git rev-parse --verify HEAD) || exit 1
SOURCE_TREE=$(git rev-parse "$SOURCE_SHA^{tree}") || exit 1
SOURCE_STATUS=$(git status --porcelain=v1 --untracked-files=all) || exit 1
[ -z "$SOURCE_STATUS" ] || { echo "tracked and untracked source must be clean before release preparation"; exit 1; }
SOURCE_HIDDEN=$(git ls-files -v | LC_ALL=C awk '/^[a-zS]/ { n++ } END { print n + 0 }') || exit 1
if [ "$SOURCE_HIDDEN" -ne 0 ]; then
  echo "assume-unchanged/skip-worktree flags hide source changes; remove them before release preparation"
  exit 1
fi

TEAM=UUSSWWML2A
BUNDLE=com.forit.openglasses.dolores
WIDGET_BUNDLE=$BUNDLE.activity-widget
APP_PROFILE_NAME="OpenGlasses App Store"
WIDGET_PROFILE_NAME="OpenGlasses Widget App Store"
APP_STORE_ID=6761319043  # the "ForIT Glasses" App Store Connect record
export ASC_KEY_ID=${ASC_KEY_ID:-78ND83SSBB}
export ASC_ISSUER_ID=${ASC_ISSUER_ID:-b21bbf92-e667-43f9-b358-29908a814489}
CERT_DIR=${CERT_DIR:-$HOME/AppleCerts}
KEY=${ASC_KEY_PATH:-$CERT_DIR/AuthKey_$ASC_KEY_ID.p8}
WHATS_NEW=${WHATS_NEW:-}
PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
XCODE_PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
CI_SIM=/Users/Shared/ci-sim
LANE_SIM=("$CI_SIM/ci-sim-lane.sh" --lane OpenGlasses)  # this lane's simulator, and nobody else's
MINI_GATE=/Users/Shared/forit-gate/mini-gate.sh
ASC_PROVISION=build/spm/checkouts/for-iCommon/Scripts/asc/asc_provision.py  # ForITCommon's, resolved by the tests
COMMON_REPOSITORY=https://github.com/ForITLLC/for-iCommon.git
COMMON_VERSION=0.31.5
COMMON_REVISION=d6f69ba013783b0aab33a8233af4a5331dd9ddc1
COMMON_TAG_OBJECT=4a7b35a75c9384f8cabb7271185c86a43b0363e4
COMMON_JOB_TEMP=""
PACKAGE_RESOLUTION=OpenGlasses.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
OUT=build/testflight-$(date -u +%Y%m%dT%H%M%SZ)
TESTED_APP=$PWD/build/dd-sim/Build/Products/Debug-iphonesimulator/OpenGlasses.app
GATE_SCREENS_ROOT=${FORIT_SCREENS_ROOT:-/Users/Shared/forit-screens}
KC=$PWD/build/signing-$$.keychain-db
KCPW=""
KC_MADE="" SIM_UDID="" GATE_RUN_ACTIVE="" PLISTS_PATCHED=""
INFO_PLISTS=(OpenGlasses/Info.plist GlassesActivityWidget/Info.plist)
mkdir -p "$OUT"
[ -n "$MATRIX_PR" ] || mkdir -p "$PROFILES_DIR"
echo "logs in $OUT"

step() {  # step <name> <cmd...>: prints "step <name> rc=<rc> <seconds>s", log in $OUT
  local name=$1 start rc
  shift
  start=$(date +%s)
  "$@" > "$OUT/$name.log" 2>&1
  rc=$?
  echo "step $name rc=$rc $(( $(date +%s) - start ))s"
  [ $rc -eq 0 ] || { tail -25 "$OUT/$name.log"; exit $rc; }
}

capture_gate_matrix() {
  # The first sheet can precede the human PR checklist. Preserve the real gate result;
  # matrix_proof accepts rc=1 only when that checklist is the sole failed static check.
  local start rc
  start=$(date +%s)
  "$@" > "$OUT/gate-matrix.log" 2>&1
  rc=$?
  printf '%s\n' "$rc" > "$OUT/gate-matrix.exit"
  echo "step gate-matrix rc=$rc $(( $(date +%s) - start ))s; capture proof still requires validation"
  case "$rc" in
    0 | 1) return 0 ;;
    *) tail -25 "$OUT/gate-matrix.log"; exit "$rc" ;;
  esac
}

keychain_first() {  # unlock $KC and put it first in the user search list; other jobs on the Mini rewrite that list
  local rest
  security unlock-keychain -p "$KCPW" "$KC"
  rest=$(security list-keychains -d user | tr -d '"' | grep -v -F "$KC")
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KC" $rest
}

restore_plists() {  # put back the Info.plists xcodegen generated (the archive gave them this run's build number)
  local p
  [ -n "$PLISTS_PATCHED" ] || return 0
  for p in "${INFO_PLISTS[@]}"; do
    cp "$OUT/$(dirname "$p")-Info.plist.orig" "$p"
  done
  PLISTS_PATCHED=""
}

end_gate_run() {
  [ -n "$GATE_RUN_ACTIVE" ] || return 0
  local rc
  "$MINI_GATE" --run-end
  rc=$?
  if [ "$rc" -eq 0 ]; then GATE_RUN_ACTIVE=""; unset FORIT_GATE_RUN; fi
  return "$rc"
}

cleanup() {
  local rc=$? rest
  trap '' INT TERM HUP
  if [ -n "$GATE_RUN_ACTIVE" ]; then
    end_gate_run > "$OUT/gate-run-cleanup.log" 2>&1 || {
      echo "could not end the shared gate run (see $OUT/gate-run-cleanup.log)"
      [ "$rc" -ne 0 ] || rc=1
    }
  fi
  restore_plists
  if [ -n "$KC_MADE" ]; then
    rest=$(security list-keychains -d user | tr -d '"' | grep -v -F "$KC")
    # shellcheck disable=SC2086
    security list-keychains -d user -s $rest
    security delete-keychain "$KC" 2>/dev/null
  fi
  # Preserve source if the maintained run could not end; never remove another job's checkout.
  if [ -n "$COMMON_JOB_TEMP" ] && [ -z "$GATE_RUN_ACTIVE" ]; then
    rm -rf "$COMMON_JOB_TEMP" || { [ "$rc" -ne 0 ] || rc=1; }
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

prepare_common_source() {
  COMMON_JOB_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/openglasses-common.XXXXXXXX") || return 1
  COMMON_JOB_TEMP=$(cd "$COMMON_JOB_TEMP" && pwd -P) || return 1
  case "$COMMON_JOB_TEMP/" in
    "$PWD/"*) echo "Common tool checkout must be outside the app repository"; return 1 ;;
  esac
  export FORIT_COMMON_ROOT="$COMMON_JOB_TEMP/for-iCommon"
  # Use the runner's existing Git credentials. Keep the official stored origin;
  # suppress transport diagnostics rather than risk logging credential rewrites.
  GIT_TERMINAL_PROMPT=0 git clone -q --no-checkout "$COMMON_REPOSITORY" "$FORIT_COMMON_ROOT" > /dev/null 2>&1 ||
    { echo "official Common clone failed using the runner's existing Git credentials"; return 1; }
  git -C "$FORIT_COMMON_ROOT" checkout -q --detach "$COMMON_REVISION" || return 1
  [ "$(git -C "$FORIT_COMMON_ROOT" rev-parse HEAD)" = "$COMMON_REVISION" ] &&
    [ "$(git -C "$FORIT_COMMON_ROOT" rev-parse "refs/tags/$COMMON_VERSION")" = "$COMMON_TAG_OBJECT" ] &&
    [ "$(git -C "$FORIT_COMMON_ROOT" rev-parse "refs/tags/$COMMON_VERSION^{commit}")" = "$COMMON_REVISION" ] ||
    { echo "Common checkout or published tag differs from the bound release"; return 1; }
  local status
  status=$(git -C "$FORIT_COMMON_ROOT" status --porcelain=v1 --untracked-files=all) || return 1
  [ -z "$status" ] || { echo "Common tool checkout is not clean"; return 1; }
  # The existing helper authenticates the stored official origin, annotated tag,
  # exporter working bytes and canonical Git objects before either exporter runs.
  python3 -I -B "$PWD/Scripts/prepare-shared-bridges.py" \
    --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/DoloresWatch" || return 1
  python3 -I -B "$PWD/Scripts/prepare-shared-bridges.py" \
    --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/GlassesActivityWidget" || return 1
  status=$(git -C "$FORIT_COMMON_ROOT" status --porcelain=v1 --untracked-files=all) || return 1
  [ -z "$status" ] || { echo "Common exporter changed its source checkout"; return 1; }
}

retain_package_resolution() {
  python3 -I -B - "$PACKAGE_RESOLUTION" "$OUT/Package.resolved" "$COMMON_VERSION" "$COMMON_REVISION" "$MATRIX_PR" "$OUT/matrix/Package.resolved" <<'PY_RESOLUTION'
import json, pathlib, sys
source, retained = map(pathlib.Path, sys.argv[1:3])
def pins_of(resolution):
    return resolution.get("pins") or (resolution.get("object") or {}).get("pins") or []
def closure(resolution):
    return sorted(((pin.get("identity") or pin.get("package") or "").lower(),
                   pin.get("location") or pin.get("repositoryURL") or "",
                   json.dumps(pin.get("state") or {}, sort_keys=True, separators=(",", ":")))
                  for pin in pins_of(resolution))
try:
    raw = source.read_bytes()
    resolution = json.loads(raw)
    pins = pins_of(resolution)
    common = [pin for pin in pins if (pin.get("identity") or pin.get("package") or "").lower() == "for-icommon"]
    if len(common) != 1 or common[0].get("state", {}).get("version") != sys.argv[3] or common[0].get("state", {}).get("revision") != sys.argv[4]:
        raise ValueError("actual resolution does not bind the published Common release")
    if not sys.argv[5] and closure(resolution) != closure(json.loads(pathlib.Path(sys.argv[6]).read_bytes())):
        raise ValueError("upload resolution changed the tested matrix package closure")
    retained.write_bytes(raw)
    print("retained actual Xcode Package.resolved with the exact Common release")
except (OSError, ValueError, TypeError, AttributeError) as error:
    sys.exit("package resolution failed: " + str(error))
PY_RESOLUTION
}

# signing_retry <cmd...>: $KC first in the search list before each try. -exportArchive has no keychain option and
# another job can reorder the list mid-run, so only errSecInternalComponent is retried, up to 3 tries.
signing_retry() {
  local try rc=1 log
  log=$(mktemp)
  for try in 1 2 3; do
    keychain_first
    "$@" > "$log" 2>&1
    rc=$?
    cat "$log"
    if [ $rc -eq 0 ] || ! grep -q errSecInternalComponent "$log"; then break; fi
    echo "signing try $try of 3: errSecInternalComponent"
  done
  rm -f "$log"
  return $rc
}

profile_field() {  # profile_field <file> <key>: one field of a signed profile's plist
  security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null
}

profile_certs() {  # profile_certs <file>: SHA-1 of each certificate the profile is bound to, one per line
  security cms -D -i "$1" 2>/dev/null | python3 -c '
import hashlib, plistlib, sys
for c in plistlib.loads(sys.stdin.buffer.read()).get("DeveloperCertificates", []):
    print(hashlib.sha1(c).hexdigest().upper())'
}

# Xcode finds project.yml's profiles by NAME among the installed ones. A copy from an earlier run whose profile has
# since been replaced in App Store Connect carries the same name, so only the one just made stays installed. Only
# files named exactly like one of this app's two profiles are ever removed.
prune_installed() {  # prune_installed <profile name> <uuid to keep>
  local dir f
  for dir in "$PROFILES_DIR" "$XCODE_PROFILES_DIR"; do
    for f in "$dir"/*.mobileprovision; do
      [ -e "$f" ] || continue
      [ "$(basename "$f" .mobileprovision)" = "$2" ] && continue
      if [ "$(profile_field "$f" Name)" = "$1" ]; then
        rm -f "$f" && echo "removed an older installed '$1': $f"
      fi
    done
  done
}

# profile <key> <bundle id> <profile name>: makes or reuses the App Store profile, checks it is the one project.yml
# names and that it is bound to the certificate we sign with, installs it for Xcode and sets PROFILE_UUID.
PROFILE_UUID=""
profile() {
  local key=$1 bundle=$2 name=$3 file
  file=$OUT/profile-$key.mobileprovision
  grep -q -F "PROVISIONING_PROFILE_SPECIFIER: \"$name\"" project.yml ||
    { echo "project.yml names no profile \"$name\"; the archive would not find it"; exit 1; }
  step "profile-$key" python3 "$ASC_PROVISION" profile --type IOS_APP_STORE --name "$name" \
    --bundle-id "$bundle" --cert-der "$CERT_DIR/distribution.der" --error-title "$name" --out "$file"
  PROFILE_UUID=$(profile_field "$file" UUID)
  [ -n "$PROFILE_UUID" ] || { echo "no UUID in $file"; exit 1; }
  profile_certs "$file" | grep -q -x "$CERT" ||
    { echo "'$name' ($PROFILE_UUID) is not bound to the certificate in $CERT_DIR/distribution.der ($CERT)"; exit 1; }
  cp "$file" "$PROFILES_DIR/$PROFILE_UUID.mobileprovision"
  prune_installed "$name" "$PROFILE_UUID"
  echo "profile $key $PROFILE_UUID ($name)"
}

make_keychain() {
  KCPW=$(openssl rand -hex 24)
  security create-keychain -p "$KCPW" "$KC" || return 1
  KC_MADE=1
  security set-keychain-settings -lut 3600 "$KC" &&
    security unlock-keychain -p "$KCPW" "$KC" &&
    security import "$CERT_DIR/distribution.key" -k "$KC" -t priv -T /usr/bin/codesign -T /usr/bin/security &&
    security import "$CERT_DIR/distribution.der" -k "$KC" -t cert &&
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" > /dev/null &&
    keychain_first &&
    security find-identity -v -p codesigning "$KC" | grep -F "$CERT"
}

record_tested_app() {
  python3 - "$TESTED_APP" "$OUT" "$SOURCE_SHA" "$SOURCE_ORIGIN" "" "$SOURCE_TREE" <<'PY_APP'
import hashlib, json, os, pathlib, plistlib, re, stat, sys
app, out = map(pathlib.Path, sys.argv[1:3])
sha, origin, upload_build, tree = sys.argv[3:]
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): value.update(block)
    return value.hexdigest()
def bundle_manifest(root):
    if root.is_symlink() or not root.is_dir(): raise ValueError("app root must be a real directory")
    def walk_error(error): raise error
    paths = [root]
    for directory, directories, files in os.walk(root, followlinks=False, onerror=walk_error):
        paths.extend(pathlib.Path(directory) / name for name in sorted(directories + files))
    entries = []
    for path in paths:
        state = path.lstat()
        entry = {"path": path.relative_to(root).as_posix(), "mode": stat.S_IMODE(state.st_mode)}
        if stat.S_ISLNK(state.st_mode):
            target = path.resolve(strict=True)
            if target != root.resolve() and root.resolve() not in target.parents:
                raise ValueError("app contains an external symlink")
            entry.update(kind="symlink", target=os.readlink(path))
        elif stat.S_ISREG(state.st_mode): entry.update(kind="file", size=state.st_size, sha256=digest(path))
        elif stat.S_ISDIR(state.st_mode): entry.update(kind="directory")
        else: raise ValueError("app contains an unsupported filesystem entry")
        entries.append(entry)
    return sorted(entries, key=lambda entry: entry["path"])
def manifest_digest(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
try:
    with (app / "Info.plist").open("rb") as stream: info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "com.forit.openglasses.dolores":
        raise ValueError("the tested product is not OpenGlasses")
    if info.get("DTPlatformName") != "iphonesimulator" and "iPhoneSimulator" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("the tested app is not an iOS simulator product")
    executable = info.get("CFBundleExecutable", "")
    if not executable or pathlib.Path(executable).name != executable or not (app / executable).is_file():
        raise ValueError("the tested app executable is missing or invalid")
    version, build = (str(info.get(key, "")) for key in ("CFBundleShortVersionString", "CFBundleVersion"))
    if any(not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value) for value in (version, build)):
        raise ValueError("the tested app has unresolved marketing/build values")
    resolution = pathlib.Path("OpenGlasses.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    raw = resolution.read_bytes()
    resolved = json.loads(raw)
    pins = resolved.get("pins") or (resolved.get("object") or {}).get("pins") or []
    packages = []
    for pin in pins:
        name, state = (pin.get("identity") or pin.get("package") or "").lower(), pin.get("state") or {}
        revision = state.get("revision") or ""
        if not name or not re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", revision):
            raise ValueError("the tested package resolution has an invalid pin")
        packages.append({"identity": name, "version": state.get("version") or state.get("branch") or "-", "revision": revision})
    packages.sort(key=lambda package: package["identity"])
    if not any(package["identity"] == "for-icommon" for package in packages):
        raise ValueError("the tested package resolution has no ForITCommon pin")
    manifest = bundle_manifest(app)
    (out / "tested-Package.resolved").write_bytes(raw)
    (out / "tested-PACKAGES").write_text("".join(f'{p["identity"]} {p["version"]} {p["revision"]}\n' for p in packages))
    (out / "tested-app.json").write_text(json.dumps({"source_sha": sha, "source_tree": tree, "origin": origin,
        "app_path": str(app), "bundle_id": info["CFBundleIdentifier"], "executable": executable,
        "executable_sha256": digest(app / executable), "version": version, "build": build,
        "app_bundle_manifest": manifest, "app_bundle_sha256": manifest_digest(manifest),
        "package_resolution_sha256": hashlib.sha256(raw).hexdigest(), "packages": packages,
        "intended_upload": None}, indent=2) + "\n")
    (out / "captured-version.tsv").write_text(version + "\t" + build + "\n")
    print("recorded tested simulator app identity and %d package pins; intended upload build kept separately" % len(packages))
except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
    sys.exit("tested app identity failed: " + str(error))
PY_APP
}

matrix_proof() {
  python3 - "$OUT" "$GATE_SCREENS_ROOT" "$1" "$SOURCE_SHA" "$SOURCE_TREE" "$SOURCE_ORIGIN" "$TESTED_APP" "$MATRIX_PR" <<'PY_PROOF'
import collections, csv, hashlib, json, os, pathlib, plistlib, re, shutil, stat, struct, subprocess, sys
out, root = (pathlib.Path(value).resolve() for value in sys.argv[1:3])
mode, sha, tree, origin, app_path, pr = sys.argv[3:]
app = pathlib.Path(app_path)
origins = {"https://github.com/ForITLLC/OpenGlasses", "https://github.com/ForITLLC/OpenGlasses.git",
           "git@github.com:ForITLLC/OpenGlasses.git", "ssh://git@github.com/ForITLLC/OpenGlasses.git"}
screens = ("gate", "home", "detail", "settings", "launch")
devices = ("iphone", "ipad", "ipad-landscape", "ipad-split")
gaps = ("iphone-se", "iphone-max")
def cells(kinds):
    return {(device, screen, look) for device in kinds for screen in screens for look in ("light", "dark", "ax5")} | {
        (device, "profile-menu", look) for device in kinds for look in ("light", "dark")}
expected, gap_cells = cells(devices), cells(gaps)
names = {f"{device}-{screen}-{look}.png" for device, screen, look in expected}
vs1 = {f"{device}-{screen}-{look}.png" for device in ("iphone", "ipad")
       for screen in (*screens, "profile-menu") for look in ("light", "dark")}
def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""): value.update(block)
    return value.hexdigest()
def bundle_manifest(root):
    if root.is_symlink() or not root.is_dir(): raise ValueError("app root must be a real directory")
    def walk_error(error): raise error
    paths = [root]
    for directory, directories, files in os.walk(root, followlinks=False, onerror=walk_error):
        paths.extend(pathlib.Path(directory) / name for name in sorted(directories + files))
    entries = []
    for path in paths:
        state = path.lstat()
        entry = {"path": path.relative_to(root).as_posix(), "mode": stat.S_IMODE(state.st_mode)}
        if stat.S_ISLNK(state.st_mode):
            target = path.resolve(strict=True)
            if target != root.resolve() and root.resolve() not in target.parents:
                raise ValueError("app contains an external symlink")
            entry.update(kind="symlink", target=os.readlink(path))
        elif stat.S_ISREG(state.st_mode): entry.update(kind="file", size=state.st_size, sha256=digest(path))
        elif stat.S_ISDIR(state.st_mode): entry.update(kind="directory")
        else: raise ValueError("app contains an unsupported filesystem entry")
        entries.append(entry)
    return sorted(entries, key=lambda entry: entry["path"])
def manifest_digest(entries):
    return hashlib.sha256(json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
def require(condition, reason):
    if not condition: raise ValueError(reason)
def capture_verdict(lines, code, source_sha=None):
    source_sha = source_sha or sha
    require(code in (0, 1), "shared gate crashed or returned an unexpected status")
    require(not any("Traceback (most recent call last):" in line or "gate crashed" in line for line in lines), "shared gate crashed")
    green = "mini-gate: GREEN " + source_sha[:7]
    red = "mini-gate: RED: no TestFlight build of " + source_sha[:7]
    results = [match.groups() for line in lines if (match := re.fullmatch(r"(PASS|FAIL|WARN|WAIVED)\s+(\S+)\s+(.+)", line.rstrip()))]
    failed = [row for row in results if row[0] == "FAIL"]
    if code == 0:
        require(any(line.strip() == green for line in lines) and not failed and not any(line.strip() == red for line in lines),
                "no consistent green gate for this exact source")
        return {"exit_code": 0, "status": "green", "source_sha": source_sha}
    expected_ids = collections.Counter(["CFG", "PK-1", "SI-1", "FB-1", "NC-1", "BR-2", "ID-3", "PL-1", "ED-1", "OF-1",
                                       "PL-2..5", "NC-1", "VS-1", "TR-1", "BE-1", "NT-1", "CI-4", "PL-6", "PR"])
    require(collections.Counter(row[1] for row in results) == expected_ids, "incomplete or changed static gate result set")
    require(len(failed) == 1 and failed[0][1:] == ("PR", "Judged by the lane: the PR body's checklist"),
            "a static check other than the human PR checklist failed")
    summaries = [match.groups() for line in lines if (match := re.match(r"^forit-gate: (\d+) failed, (\d+) warned, (\d+) waived, (\d+) passed \(", line))]
    counts = collections.Counter(row[0] for row in results)
    require(len(summaries) == 1 and tuple(map(int, summaries[0])) ==
            (1, counts["WARN"], counts["WAIVED"], counts["PASS"]), "gate summary does not confirm only the checklist failed")
    require(any(line.strip() == red for line in lines) and not any(line.strip() == green for line in lines), "missing exact-source RED verdict")
    return {"exit_code": 1, "status": "pending-human-review", "source_sha": source_sha, "failed_checks": ["PR"]}
def rows_of(folder):
    with (folder / "MATRIX.tsv").open(newline="") as stream: rows = list(csv.reader(stream, delimiter="\t"))
    require(all(len(row) == 4 for row in rows), "malformed full matrix rows")
    keys = [tuple(row[:3]) for row in rows]
    require(len(keys) == len(set(keys)) and set(keys) == expected | gap_cells, "incomplete or duplicate full PR grid")
    require(all(row[3] == "ok" if tuple(row[:3]) in expected else row[3].startswith("not drawn:") for row in rows),
            "full PR grid has failures, missing captures or unapproved SE/Max captures")
    with (folder / "CELLS.tsv").open(newline="") as stream: listed = list(csv.reader(stream, delimiter="\t"))
    require(len(listed) == len(keys) and {tuple(row) for row in listed} == set(keys), "CELLS.tsv disagrees with the full PR grid")
    return rows
def source_of(identity):
    source = identity["source_sha"]
    require(re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", source), "invalid capture source commit")
    result = subprocess.run(["git", "rev-parse", "--verify", source + "^{tree}"], capture_output=True, text=True)
    require(result.returncode == 0 and result.stdout.strip() == tree == identity["source_tree"],
            "capture source commit does not resolve to this exact Git tree")
def identity_of(folder, fresh=False, build_folder=None):
    identity = json.loads((folder / "tested-app.json").read_text())
    source_of(identity)
    require(identity["origin"] in origins and identity["bundle_id"] == "com.forit.openglasses.dolores", "wrong capture repository/app")
    require(pathlib.Path(identity["executable"]).name == identity["executable"], "invalid executable name")
    require(identity["executable_sha256"] == digest(app / identity["executable"]), "tested executable hash differs")
    require(actual_manifest == identity["app_bundle_manifest"] and
            manifest_digest(actual_manifest) == identity["app_bundle_sha256"], "complete tested app bundle differs")
    with (app / "Info.plist").open("rb") as stream: info = plistlib.load(stream)
    require(info.get("DTPlatformName") == "iphonesimulator" or "iPhoneSimulator" in info.get("CFBundleSupportedPlatforms", []),
            "retained app is not an iOS simulator product")
    require(info.get("CFBundleIdentifier") == identity["bundle_id"] and
            info.get("CFBundleExecutable") == identity["executable"] and
            str(info.get("CFBundleShortVersionString")) == identity["version"] and
            str(info.get("CFBundleVersion")) == identity["build"], "tested app Info.plist differs")
    resolution = pathlib.Path("OpenGlasses.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    resolved_file = folder / ("tested-Package.resolved" if fresh else "Package.resolved")
    packages_file = folder / ("tested-PACKAGES" if fresh else "PACKAGES")
    require(digest(resolution) == digest(resolved_file) == identity["package_resolution_sha256"],
            "tested package resolution differs")
    resolved = json.loads(resolved_file.read_text())
    pins = resolved.get("pins") or (resolved.get("object") or {}).get("pins") or []
    normalized = sorted(f'{(p.get("identity") or p.get("package") or "?").lower()} '
                        f'{p["state"].get("version") or p["state"].get("branch") or "-"} '
                        f'{p["state"].get("revision") or "-"}' for p in pins)
    require(packages_file.read_text() == "\n".join(normalized) + "\n", "package receipt differs from its pins")
    require(((build_folder or folder) / "BUILD").read_text().strip() == f'{identity["version"]} ({identity["build"]}) {identity["source_sha"]}',
            "captured Debug BUILD identity differs")
    return identity
def preserved_receipt(raw=None):
    candidates = sorted((path for path in out.parent.glob("testflight-*/matrix-verification.json") if path.parent != out), reverse=True)[:20]
    why = "no retained full PR receipt"
    for path in candidates:
        try:
            receipt = json.loads(path.read_text())
            require(receipt.get("schema_version") == 3 and receipt.get("scope") == "full-pr" and receipt.get("full_pr_grid_verified") is True,
                    "receipt is not a verified full PR grid")
            folder = path.parent / "matrix"
            identity = identity_of(folder)
            require(receipt["captured_app"] == identity and receipt["source_tree"] == tree, "receipt identity/tree mismatch")
            gate = receipt["capture_gate"]
            source_of({"source_sha": gate["source_sha"], "source_tree": tree})
            require(digest(folder / "capture-gate.log") == gate["log_sha256"], "retained capture gate log hash mismatch")
            parsed = capture_verdict((folder / "capture-gate.log").read_text().splitlines(),
                                     int((folder / "capture-gate.exit").read_text()), gate["source_sha"])
            require(all(gate.get(key) == value for key, value in parsed.items()), "retained capture gate verdict mismatch")
            rows = rows_of(folder)
            images = {pathlib.Path(item["file"]).name: item for item in receipt["images"]}
            require(len(receipt["images"]) == len(images) == len(names) and set(images) == names, "receipt omits full PR images")
            for name, image in images.items():
                saved = (path.parent / image["file"]).resolve()
                require(saved.parent == folder.resolve() and digest(saved) == image["sha256"], "retained PNG path/hash mismatch")
                if raw is not None: require(digest(raw / name) == image["sha256"], "shared cached PNG differs from the identity receipt")
            return folder, identity, rows, {"receipt": str(path), "sha256": digest(path), "capture_source_sha": identity["source_sha"]}
        except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
            why = str(error)
    raise ValueError(f"no matching full capture identity receipt among {len(candidates)} retained runs: {why}; "
                     "run --matrix-pr <number> once on the merge-ready tree under the owner's capture GO")
try:
    actual_manifest = bundle_manifest(app)
    with pathlib.Path("forit-app.json").open() as stream:
        declared = [entry["name"] for entry in json.load(stream)["screens"]["list"]]
    require(len(declared) == 5 and set(declared) == set(screens), "the five approved scenes changed")
    reuse = None
    verdict = None
    if mode == "reuse":
        source, identity, rows, reuse = preserved_receipt()
        verdict = json.loads(pathlib.Path(reuse["receipt"]).read_text())["capture_gate"]
    else:
        source = root / "_pr" / ("OpenGlasses-" + pr)
        with (out / "gate-matrix.log").open() as stream: lines = list(stream)
        verdict = capture_verdict(lines, int((out / "gate-matrix.exit").read_text().strip()))
        verdict["log_sha256"] = digest(out / "gate-matrix.log")
        require(not any("device matrix had failures" in line or "shards stopped early" in line for line in lines), "shared matrix failures")
        rows = rows_of(source)
        require({path.name for path in source.glob("*.png")} == names, "missing or unapproved actual PNGs")
        # A warning can say an old result existed but was redrawn. Require the actual
        # fresh full-grid summary; otherwise every reused image needs an identity receipt.
        fresh = any(line.startswith("device-matrix: 68 taken, 0 failed, 34 not drawn (") for line in lines)
        if not fresh:
            _, identity, _, reuse = preserved_receipt(source)
        else:
            identity = json.loads((out / "tested-app.json").read_text())
            require(identity["source_sha"] == sha and identity["source_tree"] == tree, "capture source changed")
            source_of(identity)
            require(digest(app / identity["executable"]) == identity["executable_sha256"], "tested executable changed")
            identity_of(out, fresh=True, build_folder=source)
    retained = out / "matrix"
    retained.mkdir(exist_ok=False)
    for name in ("BUILD", "MATRIX.tsv", "CELLS.tsv", "PACKAGES", "Package.resolved", "tested-app.json"):
        # Shared cached metadata may name the new source; retain the original identity receipt instead.
        if reuse:
            original = pathlib.Path(reuse["receipt"]).parent / "matrix" / name
        elif name in ("PACKAGES", "Package.resolved", "tested-app.json"):
            original = out / ("tested-" + name if name != "tested-app.json" else name)
        else:
            original = source / name
        shutil.copy2(original, retained / name)
    for name, original_name in (("capture-gate.log", "gate-matrix.log"), ("capture-gate.exit", "gate-matrix.exit")):
        original = pathlib.Path(reuse["receipt"]).parent / "matrix" / name if mode == "reuse" else out / original_name
        shutil.copy2(original, retained / name)
    images = []
    for name in sorted(names):
        path = retained / name
        shutil.copy2(source / name, path)
        with path.open("rb") as stream: header = stream.read(24)
        require(len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR" and all(struct.unpack(">II", header[16:24])), "invalid retained PNG")
        images.append({"file": str(path.relative_to(out)), "sha256": digest(path)})
    receipt = {"schema_version": 3, "scope": "upload-reuse" if mode == "reuse" else "full-pr", "source_tree": tree,
        "capture_source_sha": identity["source_sha"], "release_source_sha": sha, "captured_app": identity,
        "capture_gate": verdict, "review_status": verdict["status"],
        "full_pr_grid_verified": True, "full_six_device_coverage": False, "boot_kinds": ["iPhone", "iPad"],
        "captured_devices": devices, "not_drawn_rows": [row for row in rows if tuple(row[:3]) in gap_cells],
        "upload_vs1_images": sorted(vs1), "cache_reuse": reuse, "images": images,
        "uncovered_distribution": ["Mac", "Vision", "Watch"], "retained_artifact_directory": str(retained)}
    (out / "matrix-verification.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("retained full PR proof: 68 actual PNGs, 34 SE/Max gaps, 24 upload VS-1 cells; " +
          ("reused with no test/boot/matrix" if mode == "reuse" else "capture verified; " + verdict["status"]))
except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
    sys.exit("matrix proof failed: " + str(error))
PY_PROOF
}

# --- before anything runs: what the run needs is here ------------------------------------------------------------
if [ -z "$MATRIX_PR" ]; then
  for f in "$KEY" "$CERT_DIR/distribution.der" "$CERT_DIR/distribution.key"; do
    [ -r "$f" ] || { echo "missing $f"; exit 1; }
  done
fi
command -v xcodegen > /dev/null || { echo "no xcodegen on PATH (brew install xcodegen)"; exit 1; }
if [ -z "$MATRIX_PR" ]; then
  python3 -c 'import jwt, cryptography' 2> /dev/null ||
    { echo "python3 has no PyJWT or cryptography (pip3 install --user pyjwt cryptography)"; exit 1; }
fi
[ -x "$CI_SIM/ci-sim-lane.sh" ] || { echo "no $CI_SIM/ci-sim-lane.sh, the Mini's simulator route (CI-2)"; exit 1; }
[ -x "$MINI_GATE" ] || { echo "no $MINI_GATE, the required shared conformance gate (CI-1)"; exit 1; }
[ -r forit-app.json ] || { echo "no forit-app.json for the shared gate and device matrix"; exit 1; }
if [ -n "$MATRIX_PR" ]; then
  [ -n "${CI_SIM_BOOT_SLOT:-}" ] && [ -x "$CI_SIM_BOOT_SLOT" ] ||
    { echo "--matrix-pr requires an executable exported CI_SIM_BOOT_SLOT capture guard"; exit 1; }
fi
# Do not adopt or end a different lane's inherited run.
if [ -n "${FORIT_GATE_RUN:-}" ] && [ -f "$FORIT_GATE_RUN/lane" ] &&
    [ "$(cat "$FORIT_GATE_RUN/lane")" != OpenGlasses ]; then
  echo "the inherited shared gate run belongs to another lane; stopping"
  exit 1
fi

# --- 1. Secrets.plist ---------------------------------------------------------------------------------------------
if [ -n "${DOLORES_API_KEY:-}" ]; then
  cat > OpenGlasses/Secrets.plist << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>DOLORES_API_KEY</key>
  <string>${DOLORES_API_KEY}</string>
</dict>
</plist>
PLIST
  echo "Secrets.plist: DOLORES_API_KEY from the environment"
else
  cat > OpenGlasses/Secrets.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLIST
  echo "Secrets.plist: no DOLORES_API_KEY set, so the app has no built-in key and asks each person for their own at onboarding"
fi

# --- 2. project and unit tests (CI-1: a red test stops the run here) ----------------------------------------------
if [ -z "$MATRIX_PR" ]; then step reuse-matrix matrix_proof reuse; fi
step common-source prepare_common_source
step xcodegen xcodegen generate
RESOLUTION_FLAGS=()
if [ -z "$MATRIX_PR" ]; then
  # Reuse the tested lock, then ask Xcode to resolve that exact graph. This is
  # actual retained resolver output, not a synthesized replacement lock.
  mkdir -p "$(dirname "$PACKAGE_RESOLUTION")" || exit 1
  cp "$OUT/matrix/Package.resolved" "$PACKAGE_RESOLUTION" || exit 1
  RESOLUTION_FLAGS=(-onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution)
fi
step resolve-packages xcodebuild -resolvePackageDependencies -project OpenGlasses.xcodeproj -scheme OpenGlasses \
  -clonedSourcePackagesDirPath build/spm -scmProvider system "${RESOLUTION_FLAGS[@]}" FORIT_COMMON_ROOT="$FORIT_COMMON_ROOT"
step package-resolution retain_package_resolution

# The first maintained gate consumes reports, before any build phase has run.
# Prepare every configured shipping target/platform in this exact workspace after
# genuine resolution. Each step propagates guard failure before simulator/build work;
# unconditional Xcode phases still repeat the same checks before compilation.
step br3-report-parents mkdir -p /tmp
step br3-app /usr/bin/python3 -I "$FORIT_COMMON_ROOT/Scripts/control-guard/control_guard.py" \
  --inputs "$PWD/Config/ControlGuard/OpenGlasses-iOS-inputs.json" \
  --report /tmp/forit-openglasses-shared-mark-OpenGlasses-iOS-br3.json --common-revision "$COMMON_REVISION"
step br3-watch /usr/bin/python3 -I "$FORIT_COMMON_ROOT/Scripts/control-guard/control_guard.py" \
  --inputs "$PWD/Config/ControlGuard/DoloresWatch-watchOS-inputs.json" \
  --report /tmp/forit-openglasses-shared-mark-DoloresWatch-watchOS-br3.json --common-revision "$COMMON_REVISION"
step br3-activity /usr/bin/python3 -I "$FORIT_COMMON_ROOT/Scripts/control-guard/control_guard.py" \
  --inputs "$PWD/Config/ControlGuard/GlassesActivityWidget-iOS-inputs.json" \
  --report /tmp/forit-openglasses-shared-mark-GlassesActivityWidget-iOS-br3.json --common-revision "$COMMON_REVISION"

if [ -n "$MATRIX_PR" ]; then

  # The shared run owns the boot through tests and the matrix. The lane helper still guards xcodebuild.
  step gate-run "$MINI_GATE" --run-begin "$PWD"
  GATE_RUN_ASSIGNMENT=$(tail -1 "$OUT/gate-run.log")
  case "$GATE_RUN_ASSIGNMENT" in
    FORIT_GATE_RUN=*) export FORIT_GATE_RUN="${GATE_RUN_ASSIGNMENT#FORIT_GATE_RUN=}" ;;
    *) echo "no run from the shared gate (see $OUT/gate-run.log)"; exit 1 ;;
  esac
  [ -n "$FORIT_GATE_RUN" ] && [ -f "$FORIT_GATE_RUN/lane" ] &&
    [ "$(cat "$FORIT_GATE_RUN/lane")" = OpenGlasses ] ||
    { echo "the shared gate did not return an OpenGlasses run"; exit 1; }
  GATE_RUN_ACTIVE=1
  step sim "$MINI_GATE" --sim iPhone
  SIM_UDID=$(tail -1 "$OUT/sim.log")
  [[ $SIM_UDID =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]] ||
    { echo "no UDID from the shared gate's --sim iPhone (see $OUT/sim.log)"; exit 1; }
  "${LANE_SIM[@]}" list 2> /dev/null | grep -F "$SIM_UDID" | sed 's/^/simulator /'

  # -parallel-testing-enabled NO: parallel testing would clone the simulator, and no device is made here.
  step tests nice -n 10 "${LANE_SIM[@]}" xcodebuild test -jobs 2 -project OpenGlasses.xcodeproj -scheme OpenGlasses \
    -destination "id=$SIM_UDID" -only-testing:OpenGlassesTests -parallel-testing-enabled NO \
    -derivedDataPath build/dd-sim -clonedSourcePackagesDirPath build/spm -scmProvider system \
    FORIT_COMMON_ROOT="$FORIT_COMMON_ROOT" CODE_SIGNING_ALLOWED=NO
  grep -E 'Executed [0-9]+ test|Test run with|\*\* TEST (SUCCEEDED|FAILED) \*\*' "$OUT/tests.log" | tail -3 | sed 's/^/  /'

  step tested-app record_tested_app
  IFS=$'\t' read -r GATE_VERSION CAPTURE_BUILD < "$OUT/captured-version.tsv" || exit 1
  step matrix-admission env CI_SIM_LANE=OpenGlasses CI_SIM_UDID="$SIM_UDID" \
    "$CI_SIM_BOOT_SLOT" "OpenGlasses iPhone $SIM_UDID"
  capture_gate_matrix env FORIT_VERSION="$GATE_VERSION" FORIT_BUILD="$CAPTURE_BUILD" MATRIX_APP_IOS="$TESTED_APP" \
    MATRIX_VS1="" MATRIX_BOOT="iPhone iPad" MATRIX_MENU=1 "$MINI_GATE" "$PWD" . --pr "$MATRIX_PR" --matrix iphone ipad
  step matrix-verify matrix_proof full
  step gate-run-end end_gate_run
  echo "full PR matrix retained in $OUT/matrix; this mode does not archive or upload"
  exit 0
fi

# --- 3. App Store Connect: the app, its internal group, the build number --------------------------------------------
ASC_KEY_BASE64=$(base64 < "$KEY" | tr -d '\n')
export ASC_KEY_BASE64 BUNDLE_ID=$BUNDLE
rm -f "$OUT/asc.out"
step asc env GITHUB_OUTPUT="$OUT/asc.out" python3 Scripts/asc_resolve.py --require
sed 's/^/  /' "$OUT/asc.log"
APPID=$(sed -n 's/^app_id=//p' "$OUT/asc.out" | tail -1)
GROUPID=$(sed -n 's/^group_id=//p' "$OUT/asc.out" | tail -1)
BUILD=$(sed -n 's/^next_build=//p' "$OUT/asc.out" | tail -1)
if [ "$APPID" != "$APP_STORE_ID" ] || [ -z "$GROUPID" ]; then
  echo "App Store Connect answered app '$APPID' group '$GROUPID' for $BUNDLE, not ForIT Glasses ($APP_STORE_ID)"
  echo "and its internal group; stopping. See $OUT/asc.log."
  exit 3
fi
case "$BUILD" in '' | *[!0-9]* | 0) echo "no build number from App Store Connect (see $OUT/asc.log)"; exit 3 ;; esac
echo "build number $BUILD (App Store Connect's latest for app $APPID, plus one)"
ARCHIVE=$OUT/OpenGlasses-$BUILD.xcarchive

# Upload reuses the retained full PR receipt; the current commit still needs a green
# conformance gate. This mode never calls --sim, tests, or another screenshot matrix.
[ "$(git rev-parse HEAD)" = "$SOURCE_SHA" ] || { echo "source commit changed during the run"; exit 1; }
step gate "$MINI_GATE" "$PWD" .
grep -qxF "mini-gate: GREEN ${SOURCE_SHA:0:7}" "$OUT/gate.log" ||
  { echo "no fresh exact-source GREEN gate for upload"; exit 1; }
step upload-intent python3 - "$OUT" "$SOURCE_SHA" "$SOURCE_TREE" "$BUILD" <<'PY_INTENT'
import hashlib, json, pathlib, sys
out = pathlib.Path(sys.argv[1])
p = out / "matrix-verification.json"
receipt = json.loads(p.read_text())
receipt["upload_gate"] = {"status": "green", "source_sha": sys.argv[2],
                          "log_sha256": hashlib.sha256((out / "gate.log").read_bytes()).hexdigest()}
receipt["intended_upload"] = {"source_sha": sys.argv[2], "source_tree": sys.argv[3], "build": sys.argv[4],
                              "version": receipt["captured_app"]["version"]}
p.write_text(json.dumps(receipt, indent=2) + "\n")
(out / "intended-version").write_text(receipt["captured_app"]["version"] + "\n")
print("recorded intended upload separately from the original Debug screenshot identity")
PY_INTENT
IFS= read -r VERSION < "$OUT/intended-version" || exit 1

# --- 4. profiles, keychain, archive -------------------------------------------------------------------------------
CERT=$(openssl x509 -inform der -in "$CERT_DIR/distribution.der" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
[ -n "$CERT" ] || { echo "could not read $CERT_DIR/distribution.der"; exit 1; }
echo "cert $CERT"
[ -r "$ASC_PROVISION" ] ||
  { echo "no $ASC_PROVISION: the tests step resolves ForITCommon 0.17.1 or later there"; exit 1; }
profile app "$BUNDLE" "$APP_PROFILE_NAME"
UUID_APP=$PROFILE_UUID
profile widget "$WIDGET_BUNDLE" "$WIDGET_PROFILE_NAME"
UUID_WIDGET=$PROFILE_UUID

step keychain make_keychain

# xcodegen writes CFBundleVersion "1" into both Info.plists (its default: project.yml gives none), so
# CURRENT_PROJECT_VERSION alone never reaches the bundles. For the archive both carry this run's build number; the
# generated files are put back right after it.
for p in "${INFO_PLISTS[@]}"; do
  cp "$p" "$OUT/$(dirname "$p")-Info.plist.orig" || exit 1
done
PLISTS_PATCHED=1
for p in "${INFO_PLISTS[@]}"; do
  plutil -replace CFBundleVersion -string "$BUILD" "$p" || exit 1
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$p" || exit 1
done

archive() {
  rm -rf "$ARCHIVE"
  nice -n 10 xcodebuild -jobs 2 -project OpenGlasses.xcodeproj -scheme OpenGlasses -configuration Release \
    -sdk iphoneos -destination generic/platform=iOS -derivedDataPath build/dd-iphoneos \
    -clonedSourcePackagesDirPath build/spm -scmProvider system \
    -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
    -archivePath "$ARCHIVE" \
    FORIT_COMMON_ROOT="$FORIT_COMMON_ROOT" \
    DEVELOPMENT_TEAM=$TEAM CURRENT_PROJECT_VERSION="$BUILD" MARKETING_VERSION="$VERSION" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$CERT" OTHER_CODE_SIGN_FLAGS="--keychain $KC" \
    ENABLE_PREVIEWS=NO ASSETCATALOG_COMPILER_SKIP_APP_STORE_DEPLOYMENT=NO \
    archive
}
step archive signing_retry archive
verify_archive() {
  python3 - "$OUT" "$ARCHIVE" "$VERSION" "$BUILD" <<'PY_ARCHIVE'
import hashlib, json, pathlib, plistlib, sys
out, archive = map(pathlib.Path, sys.argv[1:3])
version, build = sys.argv[3:]
try:
    captured = json.loads((out / "matrix/tested-app.json").read_text())
    receipt = json.loads((out / "matrix-verification.json").read_text())
    if version != captured["version"] or receipt["intended_upload"]["version"] != version or receipt["intended_upload"]["build"] != build:
        raise ValueError("intended upload version/build differs from the retained capture intent")
    resolution = pathlib.Path("OpenGlasses.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    current, retained = resolution.read_bytes(), (out / "matrix/Package.resolved").read_bytes()
    package_sha = hashlib.sha256(current).hexdigest()
    if current != retained or package_sha != captured["package_resolution_sha256"]:
        raise ValueError("archive changed the locked tested package resolution")
    app = archive / "Products/Applications/OpenGlasses.app"
    bundles = ((app, "com.forit.openglasses.dolores"),
               (app / "PlugIns/GlassesActivityWidget.appex", "com.forit.openglasses.dolores.activity-widget"))
    for bundle, bundle_id in bundles:
        with (bundle / "Info.plist").open("rb") as stream: info = plistlib.load(stream)
        if info.get("CFBundleIdentifier") != bundle_id or str(info.get("CFBundleShortVersionString")) != version or str(info.get("CFBundleVersion")) != build:
            raise ValueError("archived app/widget differs from the retained marketing version or intended build")
    (out / "archive-Package.resolved").write_bytes(current)
    (out / "archive-verification.json").write_text(json.dumps({"intended_upload": receipt["intended_upload"],
        "package_resolution_sha256": package_sha, "verified_bundles": [item[1] for item in bundles]}, indent=2) + "\n")
    print("verified locked archive packages and intended marketing/build identity on app and widget")
except (OSError, ValueError, KeyError, TypeError) as error:
    sys.exit("archive verification failed: " + str(error))
PY_ARCHIVE
}
step archive-verify verify_archive
restore_plists

# --- 5. export, check, upload -------------------------------------------------------------------------------------
options() {  # options <export|upload>: writes the export options and prints their path
  cat > "$OUT/ExportOptions-$1.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$CERT</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE</key><string>$UUID_APP</string>
    <key>$WIDGET_BUNDLE</key><string>$UUID_WIDGET</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><true/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
  echo "$OUT/ExportOptions-$1.plist"
}

# check_bundle <dir> <bundle id> <profile uuid>: one signed bundle in the exported IPA is the right bundle id at this
# build and version, carries the profile made above and is signed for distribution.
check_bundle() {
  local dir=$1 id=$2 uuid=$3 got ent
  [ -d "$dir" ] || { echo "FAIL $(basename "$dir") is not in the IPA"; return 1; }
  got=$(plutil -extract CFBundleIdentifier raw -o - "$dir/Info.plist")
  [ "$got" = "$id" ] || { echo "FAIL $(basename "$dir") is $got, not $id"; return 1; }
  got=$(plutil -extract CFBundleVersion raw -o - "$dir/Info.plist")
  [ "$got" = "$BUILD" ] || { echo "FAIL $id CFBundleVersion is $got, not $BUILD"; return 1; }
  got=$(plutil -extract CFBundleShortVersionString raw -o - "$dir/Info.plist")
  [ "$got" = "$VERSION" ] || { echo "FAIL $id version is $got, the app's is $VERSION"; return 1; }
  got=$(profile_field "$dir/embedded.mobileprovision" UUID)
  [ "$got" = "$uuid" ] || { echo "FAIL $id is signed with profile ${got:-none}, not $uuid"; return 1; }
  ent=$(codesign -d --entitlements - --xml "$dir" 2> /dev/null)
  got=$(plutil -extract application-identifier raw -o - - <<< "$ent" 2> /dev/null)
  [ "$got" = "$TEAM.$id" ] || { echo "FAIL $id application-identifier is ${got:-missing}"; return 1; }
  got=$(plutil -extract get-task-allow raw -o - - <<< "$ent" 2> /dev/null)
  [ "$got" != true ] || { echo "FAIL $id is signed with get-task-allow (a development signature)"; return 1; }
  echo "ok $id build $BUILD ($VERSION) profile $uuid"
}

verify_ipa() {
  local root=$OUT/verify ipa="" f app
  for f in "$OUT"/export/*.ipa; do [ -f "$f" ] && ipa=$f; done
  [ -n "$ipa" ] || { echo "FAIL no .ipa in $OUT/export"; return 1; }
  rm -rf "$root" && ditto -x -k "$ipa" "$root" || return 1
  app=$root/Payload/OpenGlasses.app
  [ -d "$app" ] || { echo "FAIL no OpenGlasses.app in $ipa"; return 1; }
  codesign --verify --deep --strict --verbose=2 "$app" || return 1
  [ -f "$app/Assets.car" ] || { echo "FAIL no Assets.car in OpenGlasses.app (the app icon)"; return 1; }
  [ ! -e "$app/Watch" ] || { echo "FAIL OpenGlasses.app embeds a Watch app; only the app and its widget are signed here"; return 1; }
  check_bundle "$app" "$BUNDLE" "$UUID_APP" &&
    check_bundle "$app/PlugIns/GlassesActivityWidget.appex" "$WIDGET_BUNDLE" "$UUID_WIDGET"
}

step export signing_retry xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$(options export)" -exportPath "$OUT/export"
step verify verify_ipa
grep -E '^ok ' "$OUT/verify.log" | sed 's/^/  /'

if [ -z "$UPLOAD" ]; then
  echo "done ForIT Glasses build $BUILD, not uploaded (--no-upload): $OUT/export"
  exit 0
fi

step pre-upload-verify verify_archive
step upload signing_retry xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$(options upload)" -exportPath "$OUT/upload" \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
echo "uploaded ForIT Glasses build $BUILD to app $APPID"
# Waits up to 20 minutes for Apple's processing; a build not VALID by then fails the step, as the workflow did.
step processing python3 Scripts/asc_attach.py --app-id "$APPID" --group-id "$GROUPID" --version "$BUILD" \
  --whats-new "$WHATS_NEW" --require-valid
grep -v -E 'not visible in ASC yet|state=PROCESSING' "$OUT/processing.log" | sed 's/^/  /'
echo "done ForIT Glasses build $BUILD"
