#!/bin/bash
# Usage: Scripts/mini-testflight.sh [--no-upload]
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
# Each step prints "step <name> rc=<rc> <seconds>s"; its log is build/testflight-<UTC time>/<name>.log.
#
# 1. OpenGlasses/Secrets.plist: DOLORES_API_KEY from the environment, written as the workflow wrote it. With no key
#    the plist holds an empty dict and the app asks each person for their own key at onboarding. The key is never
#    printed.
# 2. xcodegen generate, then the unit tests (scheme OpenGlasses, -only-testing:OpenGlassesTests) on one of the Mini's
#    stock iPhone simulators: named exactly like its device type, shut down, booted before (it has
#    data/Library/Preferences/com.apple.migration.plist) and given to no lane in /Users/Shared/ci-sim/ci-sim-lanes.conf.
#    No device is ever created. The boot goes through the Mini's boot slot (checklist CI-2), and the simulator is shut
#    down again after the tests. A red test stops the run before anything is signed (CI-1).
# 3. App Store Connect (Scripts/asc_resolve.py, read-only): the app record (must be 6761319043), its internal group
#    "ForIT Internal", and the build number: the highest build number App Store Connect has for the app, plus one,
#    the rule the workflow used.
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

USAGE="usage: Scripts/mini-testflight.sh [--no-upload]"
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD="" ;;
    -h | --help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
done

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
ASC_PROVISION=build/spm/checkouts/for-iCommon/Scripts/asc/asc_provision.py  # ForITCommon's, resolved by the tests
OUT=build/testflight-$(date -u +%Y%m%dT%H%M%SZ)
KC=$PWD/build/signing-$$.keychain-db
KCPW=""
KC_MADE="" SIM_UDID="" SIM_BOOTED="" PLISTS_PATCHED=""
INFO_PLISTS=(OpenGlasses/Info.plist GlassesActivityWidget/Info.plist)
mkdir -p "$OUT" "$PROFILES_DIR"
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

within() {  # within <seconds> <cmd...>: the command, killed when it outlives the deadline (macOS has no timeout(1))
  local secs=$1
  shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
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

shutdown_sim() {
  [ -n "$SIM_BOOTED" ] || return 0
  within 60 "$SIMCTL" shutdown "$SIM_UDID" > /dev/null 2>&1 || echo "could not shut down simulator $SIM_UDID"
  SIM_BOOTED=""
}

cleanup() {
  local rest
  shutdown_sim
  restore_plists
  if [ -n "$KC_MADE" ]; then
    rest=$(security list-keychains -d user | tr -d '"' | grep -v -F "$KC")
    # shellcheck disable=SC2086
    security list-keychains -d user -s $rest
    security delete-keychain "$KC" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

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

# --- before anything runs: what the run needs is here ------------------------------------------------------------
for f in "$KEY" "$CERT_DIR/distribution.der" "$CERT_DIR/distribution.key"; do
  [ -r "$f" ] || { echo "missing $f"; exit 1; }
done
command -v xcodegen > /dev/null || { echo "no xcodegen on PATH (brew install xcodegen)"; exit 1; }
python3 -c 'import jwt, cryptography' 2> /dev/null ||
  { echo "python3 has no PyJWT or cryptography (pip3 install --user pyjwt cryptography)"; exit 1; }
SIMCTL=$(xcrun -f simctl) || { echo "no simctl (xcrun -f simctl)"; exit 1; }

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
step xcodegen xcodegen generate

# Candidates, newest iOS runtime first: "<udid> <runtime> <name>". Stock only (named like the device type), shut
# down, booted before (an iOS 27 simulator's first boot can hang the Mini for every lane), iOS 26 or later.
stock_iphones() {
  within 30 "$SIMCTL" list -j devices available > "$OUT/sim-devices.json" &&
    within 30 "$SIMCTL" list -j devicetypes > "$OUT/sim-devicetypes.json" || return 1
  python3 - "$OUT/sim-devices.json" "$OUT/sim-devicetypes.json" << 'PY'
import json, os, re, sys
devices = json.load(open(sys.argv[1]))["devices"]
types = {t["identifier"]: t for t in json.load(open(sys.argv[2]))["devicetypes"]}
rows = []
for runtime, devs in devices.items():
    m = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", runtime)
    if not m or int(m.group(1)) < 26:
        continue
    for d in devs:
        t = types.get(d.get("deviceTypeIdentifier"), {})
        if t.get("productFamily") != "iPhone" or d.get("name") != t.get("name"):
            continue
        if d.get("state") != "Shutdown" or not d.get("isAvailable", True):
            continue
        data = d.get("dataPath") or os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{d['udid']}/data")
        if not os.path.isfile(os.path.join(data, "Library/Preferences/com.apple.migration.plist")):
            continue
        rows.append(((int(m.group(1)), int(m.group(2))), d["udid"], d["name"]))
for (major, minor), udid, name in sorted(rows, key=lambda r: r[0], reverse=True):
    print(f"{udid} iOS-{major}.{minor} {name}")
PY
}

sim_owner() {  # the lane (repo) a simulator belongs to, "-" for none; "?" when the lane helper cannot tell
  local owner
  [ -x "$CI_SIM/ci-sim-lane.sh" ] || { echo -; return; }
  owner=$("$CI_SIM/ci-sim-lane.sh" owner "$1" < /dev/null 2> /dev/null) || owner="?"
  echo "${owner:-?}"
}

while read -r udid runtime name; do
  [ -n "$udid" ] || continue
  owner=$(sim_owner "$udid")
  if [ "$owner" != - ]; then
    echo "skip $name $runtime ($udid): lane $owner"
    continue
  fi
  SIM_UDID=$udid
  echo "simulator $name $runtime ($udid)"
  break
done < <(stock_iphones)
[ -n "$SIM_UDID" ] || {
  echo "no stock iPhone simulator here is shut down, booted before and in no lane; not creating one."
  echo "See $OUT/sim-devices.json."
  exit 1
}
"$CI_SIM/ci-sim-boot-slot.sh" "OpenGlasses unit-tests $SIM_UDID" || true
within 120 "$SIMCTL" boot "$SIM_UDID" || { echo "simctl boot $SIM_UDID failed"; exit 1; }
SIM_BOOTED=1
within 300 "$SIMCTL" bootstatus "$SIM_UDID" > "$OUT/bootstatus.log" 2>&1 ||
  { echo "simulator $SIM_UDID did not finish booting (see $OUT/bootstatus.log)"; exit 1; }

# -parallel-testing-enabled NO: parallel testing would clone the simulator, and no device is made here.
step tests nice -n 10 xcodebuild test -project OpenGlasses.xcodeproj -scheme OpenGlasses \
  -destination "id=$SIM_UDID" -only-testing:OpenGlassesTests -parallel-testing-enabled NO \
  -derivedDataPath build/dd-sim -clonedSourcePackagesDirPath build/spm -scmProvider system \
  CODE_SIGNING_ALLOWED=NO
grep -E 'Executed [0-9]+ test|Test run with|\*\* TEST (SUCCEEDED|FAILED) \*\*' "$OUT/tests.log" | tail -3 | sed 's/^/  /'
shutdown_sim

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

# --- 4. profiles, keychain, archive -------------------------------------------------------------------------------
CERT=$(openssl x509 -inform der -in "$CERT_DIR/distribution.der" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')
[ -n "$CERT" ] || { echo "could not read $CERT_DIR/distribution.der"; exit 1; }
echo "cert $CERT"
[ -r "$ASC_PROVISION" ] ||
  { echo "no $ASC_PROVISION: the tests step resolves ForITCommon 0.17.0 or later there"; exit 1; }
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
done

archive() {
  rm -rf "$ARCHIVE"
  nice -n 10 xcodebuild -project OpenGlasses.xcodeproj -scheme OpenGlasses -configuration Release \
    -sdk iphoneos -destination generic/platform=iOS -derivedDataPath build/dd-iphoneos \
    -clonedSourcePackagesDirPath build/spm -scmProvider system \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM=$TEAM CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$CERT" OTHER_CODE_SIGN_FLAGS="--keychain $KC" \
    ENABLE_PREVIEWS=NO ASSETCATALOG_COMPILER_SKIP_APP_STORE_DEPLOYMENT=NO \
    archive
}
step archive signing_retry archive
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

VERSION=""
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
  VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Info.plist")
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
