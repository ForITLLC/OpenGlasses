# Internal Distribution Pipeline — Runbook (WO#620 · D6)

How a build of **ForIT Glasses** (`com.forit.openglasses.dolores`) gets cut, signed,
uploaded, and made installable to ForIT staff. Builds 18 & 19 (2026-07-24) were verified end-to-end
through the old GitHub workflow; since 2026-10-12 the same steps run by hand on the Mac mini
(ForIT checklist CI-1, CI-3: no GitHub-hosted macOS).

- **App:** ASC app `6761319043` · Team `UUSSWWML2A` (ForIT LLC) · marketing version `1.3.1`
- **Distribution:** TestFlight **Internal** → group **"ForIT Internal"** (`971212a6-200e-4b9d-82cb-433d9c5105f2`)
- **Script:** [`Scripts/mini-testflight.sh`](../Scripts/mini-testflight.sh), run on the Mac mini over ssh
- **Project generator:** XcodeGen (`project.yml`) — the `.xcodeproj` is generated on each run, not committed.

## How to cut a build

Copy the repo to the Mini and run the script there:

```bash
rsync -a --delete --exclude .git --exclude build ./ mini-lan:ci-work/OpenGlasses-ios/
ssh mini-lan 'cd ~/ci-work/OpenGlasses-ios && Scripts/mini-testflight.sh'
```

`--no-upload` stops once the signed IPA is exported and checked. Each step prints
`step <name> rc=<rc> <seconds>s` and logs to `build/testflight-<UTC time>/`.

There is nothing to bump by hand: the build number is derived automatically (see below). A fresh
build reaches the "ForIT Internal" group with **no further action**.

## What the script does (step by step)

1. **Create `Secrets.plist`** — `DOLORES_API_KEY` goes in only when it is set in the environment.
   By default the plist is empty and onboarding asks each person for their own key: a key built
   into the app can be read by anyone who has the build.
2. **Generate Xcode project** — `xcodegen` regenerates `OpenGlasses.xcodeproj` from `project.yml`.
3. **Unit tests** — `OpenGlassesTests` on one of the Mini's stock iPhone simulators, booted through
   the boot slot. A red test stops the run before anything is signed.
4. **Determine build number** — queries ASC for the current max build and sets
   `CURRENT_PROJECT_VERSION = max + 1`, so uploads never collide with an existing build.
5. **Signing** — the Apple Distribution cert + key go into a throwaway keychain; `asc_provision.py`
   makes or reuses the app and widget App Store profiles. The Watch app is not embedded.
6. **Archive** — `xcodebuild archive`, Release, `generic/platform=iOS`, manual signing.
7. **Export & Upload** — `xcodebuild -exportArchive` with `method=app-store-connect`; the IPA's
   signature, bundle ids, build number and profiles are checked before it leaves the Mini.
8. **Clear export compliance + expose to group** — `asc_attach.py` polls ASC (≤20 min) until the
   build is `VALID`, sets `usesNonExemptEncryption=false` (clears the compliance gate), then confirms
   the build is available to "ForIT Internal".

## Two facts that make this reproducible (and the bugs they fixed)

- **Meta DAT SDK is pinned `exactVersion: "0.5.0"`** in `project.yml`. `xcodegen` discards the
  checked-in `Package.resolved`, so a *floating* `from:` would let a fresh build resolve drift to a
  newer, API-incompatible SDK (0.8.0 renamed/removed `StreamSession`, `StreamSessionConfig`,
  `DeviceStateSession`, …) and the archive would compile-fail. **Do not un-pin this.**
- **"ForIT Internal" is an internal group with `hasAccessToAllBuilds=true`**, so *every* uploaded
  build is exposed to its testers automatically. App Store Connect **rejects** an explicit
  build→group assignment for such a group (`422 ENTITY_UNPROCESSABLE: "Cannot add internal group
  to a build."`). The script therefore detects the all-builds group and **skips** the (impossible)
  assignment, while failing loud on any genuinely unexpected error.

## How to verify a build is live

**App Store Connect UI:** TestFlight → iOS builds → the new build shows *Ready to Test*, and the
"ForIT Internal" group lists it.

**API (read-only), the check builds 18 & 19 were verified with:**
```bash
# build state / expiry / compliance  (needs an ASC API key)
GET /v1/builds?filter[app]=6761319043&filter[version]=<N>
     &fields[builds]=version,processingState,expired,usesNonExemptEncryption
# expect: processingState=VALID · expired=false · usesNonExemptEncryption=false
```
A healthy build: `VALID`, `expired=false`, `usesNonExemptEncryption=false`.

## How a tester installs

Testers in "ForIT Internal" install via the **TestFlight** app (App Store → TestFlight → the app →
*Install/Update*). Internal testers are explicitly-named Apple IDs — a non-member cannot install.

## Build expiry (the one operational caveat)

TestFlight builds **expire 90 days after upload** (this is why builds 10–17 all went dead). Keeping a
live build means running the script again before 90 days are up. For a *no-expiry*
end-state, see the ABM Custom App path in [`distribution-model.md`](./distribution-model.md).

## What the Mini needs

`~/AppleCerts/distribution.{key,der}` (Apple Distribution) and `~/AppleCerts/AuthKey_78ND83SSBB.p8`
(ASC key id `78ND83SSBB`, issuer `b21bbf92-e667-43f9-b358-29908a814489`); `xcodegen` and `python3`
with PyJWT in `/opt/homebrew/bin`; and GitHub read access to the private ForITLLC/for-iCommon package.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Archive fails: `cannot find type 'StreamSession'…` | DAT SDK drifted off 0.5.0 | Keep `exactVersion: "0.5.0"` in `project.yml` |
| Upload OK but build never appears in group | 422 on internal all-builds group was swallowed | Already handled — the script skips assign for all-builds groups |
| Upload rejected: duplicate build number | build# collided with ASC | Handled — build# = ASC max + 1 |
| Build stuck non-installable | export compliance not set | Handled — the script sets `usesNonExemptEncryption=false` |
