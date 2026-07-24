# Internal Distribution Pipeline — Runbook (WO#620 · D6)

How a build of **ForIT Glasses** (`com.forit.openglasses.dolores`) gets cut, signed,
uploaded, and made installable to ForIT staff — fully automated in CI and verified end-to-end
(builds 18 & 19, 2026-07-24).

- **App:** ASC app `6761319043` · Team `UUSSWWML2A` (ForIT LLC) · marketing version `1.3.1`
- **Distribution:** TestFlight **Internal** → group **"ForIT Internal"** (`971212a6-200e-4b9d-82cb-433d9c5105f2`)
- **Workflow:** [`.github/workflows/build-and-upload.yml`](../.github/workflows/build-and-upload.yml)
- **Project generator:** XcodeGen (`project.yml`) — the `.xcodeproj` is generated in CI, not committed.

## How to cut a build

Either:
1. **Push to `main`** — any change *except* docs-only (`docs/**`, `**/*.md` are `paths-ignore`d), or
2. **Manual** — Actions → "Build & Upload to App Store Connect" → *Run workflow* (`workflow_dispatch`).

There is nothing to bump by hand: the build number is derived automatically (see below). A fresh
build reaches the "ForIT Internal" group with **no further action**.

## What the pipeline does (step by step)

1. **Select Xcode** (26.2 on the `macos-26` runner, iOS 26 SDK).
2. **Install signing materials** — imports the Apple Distribution cert + key and all three
   provisioning profiles (app, watch, widget) into a temporary keychain (from GH secrets).
3. **Create `Secrets.plist`** — injects `DOLORES_API_KEY`.
4. **Generate Xcode project** — `xcodegen` regenerates `OpenGlasses.xcodeproj` from `project.yml`.
5. **Determine build number** — queries ASC for the current max build and sets
   `CURRENT_PROJECT_VERSION = max + 1`, so uploads never collide with an existing build.
6. **Archive** — `xcodebuild archive`, Release, `generic/platform=iOS`, manual signing.
7. **Export & Upload** — `xcodebuild -exportArchive` with `method=app-store-connect`,
   authenticated by the ASC API key.
8. **Clear export compliance + expose to group** — polls ASC (≤20 min) until the build is
   `VALID`, sets `usesNonExemptEncryption=false` (clears the compliance gate), then confirms the
   build is available to "ForIT Internal".

## Two facts that make this reproducible (and the bugs they fixed)

- **Meta DAT SDK is pinned `exactVersion: "0.5.0"`** in `project.yml`. `xcodegen` discards the
  checked-in `Package.resolved`, so a *floating* `from:` would let a fresh CI resolve drift to a
  newer, API-incompatible SDK (0.8.0 renamed/removed `StreamSession`, `StreamSessionConfig`,
  `DeviceStateSession`, …) and the archive would compile-fail. **Do not un-pin this.**
- **"ForIT Internal" is an internal group with `hasAccessToAllBuilds=true`**, so *every* uploaded
  build is exposed to its testers automatically. App Store Connect **rejects** an explicit
  build→group assignment for such a group (`422 ENTITY_UNPROCESSABLE: "Cannot add internal group
  to a build."`). The pipeline therefore detects the all-builds group and **skips** the (impossible)
  assignment, while failing loud on any genuinely unexpected error.

## How to verify a build is live

**App Store Connect UI:** TestFlight → iOS builds → the new build shows *Ready to Test*, and the
"ForIT Internal" group lists it.

**API (read-only), the check this pipeline was verified with:**
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

TestFlight builds **expire 90 days after upload** (this is why builds 10–17 all went dead). Because
any push re-cuts a fresh build, keeping a live build is just a matter of re-cutting before 90 days —
add a scheduled (`cron`) `workflow_dispatch` if you want it fully hands-off. For a *no-expiry*
end-state, see the ABM Custom App path in [`distribution-model.md`](./distribution-model.md).

## Required GitHub secrets

`DISTRIBUTION_CERT_BASE64`, `DISTRIBUTION_KEY_BASE64`, `PROVISIONING_PROFILE_BASE64`,
`WATCH_PROFILE_BASE64`, `WIDGET_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`, `ASC_KEY_BASE64`,
`DOLORES_API_KEY`. (ASC key id `78ND83SSBB`, issuer `b21bbf92-e667-43f9-b358-29908a814489`.)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Archive fails: `cannot find type 'StreamSession'…` | DAT SDK drifted off 0.5.0 | Keep `exactVersion: "0.5.0"` in `project.yml` |
| Upload OK but build never appears in group | 422 on internal all-builds group was swallowed | Already handled — pipeline skips assign for all-builds groups |
| Upload rejected: duplicate build number | build# collided with ASC | Handled — build# = ASC max + 1 |
| Build stuck non-installable | export compliance not set | Handled — pipeline sets `usesNonExemptEncryption=false` |
