# Meta voice launch and Bernard's voice

Ben asked for the glasses to open Bernard through Meta's own wake phrase and to choose Bernard's speaking voice. These changes build on our existing app; they do not import current upstream OpenGlasses code.

## What changes

The app pins Meta DAT **1.0.1**, the patch release in the 1.0 series. Camera and connection code use its `DeviceSession`, `Camera` and `Stream` APIs. The app keeps one Meta voice-invocation channel and restarts it after a glasses link reconnects. Cold and warm Meta callback URLs go through the same handler. A launch is acknowledged only after microphone recording starts; a permission or microphone failure is acknowledged as a failure.

Meta owns the wake phrase. The app no longer runs its old idle “Hey Bernard”/“Hey Dolores” recognizer or offers custom wake-word choices. The existing microphone button and Shortcuts remain available. During spoken replies, local speech recognition may still listen for Stop. Disabling listening closes the Meta channel, cancels unsent transcription and prevents delayed microphone retries.

Settings has a shared native Voice picker. It loads real available voices from Bernard, saves the choice on this device immediately and offers Undo. Each next voice request includes that choice. Bernard must confirm the effective voice before its returned audio is accepted. If the selected audio is unavailable, the app retains the text and announces in the app that it is using the device voice. It does not silently substitute the old phone-side ElevenLabs voice.

## Engine contract and owner

for-AI owns the engine implementation and publication; OpenGlasses owns the picker and saved selection. Existing API-key authentication remains in use. No provider key moves to the phone. The November 3 [engine publication readback](/home/runner/handoffs/OpenGlasses/ben-report-20261103/ENGINE-PUBLICATION-READBACK.json) confirms the voice contract is present in the successful normal v216 release source (`d9985328369ffe6801cd573b91306026044d83a3`), first included in v213. This is published-source evidence, not proof of the signed-in account catalogue, generated audio or a working physical voice choice.

- `GET <configured voice URL>/voices`, authenticated with `X-API-Key`, returns `defaultVoiceId` and `voices: [{id, name}]`. The legacy shared key also requires `userEmail`; a per-user key supplies its own identity.
- `POST <configured voice URL>` accepts optional `voiceId`. Omitting it retains the existing engine default. An explicit unavailable or malformed choice fails before a model turn starts.
- A reply's `voiceId` names the selected configuration. Only audio that was actually generated includes `effectiveVoiceId`, identifying the voice used for synthesis; audio remains optional. The app checks `effectiveVoiceId` against an explicit selection and rejects unconfirmed audio, including replies from an older engine that ignores the new field.

The engine's configured default need not appear in the account's current catalogue. Only the returned `voices` list establishes available explicit choices. Opening Settings never silently changes a removed or unavailable saved choice.

## Meta beta setup and hardware proof

DAT 1.0 is stable, but Voice Invocations remains **experimental and beta-only**. Updating the SDK alone does not enable or prove “Hey Meta” launch. Meta's current instructions and later maintainer correction require a release channel rather than Developer Mode for voice launch. Use the registered spoken app name, the correct beta version/channel and invited account, current glasses firmware and Meta AI app, and the “Launch with Hey Meta” setting. English (US) is the validated launch language in the maintainer's reply. Earlier permission-approval wording conflicts with that reply, so inspect the actual current developer-console state before changing it.

Meta's FAQ lists Ray-Ban Meta Gen 1 and Gen 2, Meta Ray-Ban Display, Oakley Meta HSTN and Oakley Meta Vanguard. Its omission of Gen 3 is superseded by an October 2 reply from a collaborator on Meta's official SDK repository confirming DAT 1.0 support. Some models may enumerate as `rayBanMetaOptics`; do not filter them out by accepting only `rayBanMeta`.

Ben's October 25 store receipt identifies RW4011 and UPC 8056266264771. The manufacturer's store maps that exact product to **Ray-Ban Meta Gen 3 Wayfarer, 690680, size 53-22**. A separate same-day delivery receipt also explicitly identifies Gen 3 Wayfarers. These establish the purchased model; neither receipt is a live pairing or firmware observation. The receipts remain private evidence outside the repository.

The same SDK collaborator's October 16 correction says iOS 1.0.x must create a fresh camera for each burst rather than restart a stopped stream. Stop/detach the camera and wait for its stopped state before attaching another. Opening the Bluetooth microphone can end an active DAT session on some glasses firmware; repeated microphone/camera switching still needs physical testing. Vendor guidance does not establish that our particular hardware sequence works.

Physical acceptance must include launch with the phone locked, missing permissions, disabled listening, reconnect, a failed launch acknowledgement, two successive camera captures, camera Stop during startup, and a changed engine voice. Do not use an always-on app wake recognizer or silent audio as a substitute for failed Meta background activation.

## License boundary

Our fork's common ancestor `129cfeb862818871dcdddb58c2c4c4589a3f68cc` and retained fork licence are MIT. Keep the original copyright and permission notices. Upstream switched to BSL 1.1 at `f2f2fcea9f41b2eb3c089cca16aa354e32e12bb8`; its current code carries restrictions on commercial use and distribution and offers a separate Skunkworks NZ licence. A full rebase onto that code would bring those terms with it. This change uses the official Meta SDK and our app code, avoiding that upstream code. Meta's own SDK developer terms still apply.

## Validation state

The November 3 native job `apple-OpenGlasses-f0ce609db690-15638f7b88e8` tested source `f0ce609db690a4be91440799294a169010e9dc58`: all **102 tests passed**, including the suspended-launch regressions. Archive, signing, export, one upload and cleanup passed. Apple confirmed **1.0 (33)** as VALID, export compliant and available to ForIT Internal in IN_BETA_TESTING. A fresh App Store Connect readback agrees. See the [independent final native review](/home/runner/handoffs/OpenGlasses/ben-report-20261103/F0CE609D-FINAL-NATIVE-REVIEW.json). Internal availability does not prove installation, opening on Ben’s iPhone or glasses audio.

The genuine 685-byte package lock, tested and archived copies match: Meta **1.0.1 / 0bd369298eef6a980ad0bdb6c8a5502f2c02a08c**, Common **0.31.9 / 352f567e839b8faf61b6df5840c5275b016addce**, SHA256 `377eb8e3cd13e30f0e3407633abfdbfb4001c2cf10d7dad3e7845f063b22293c`. No pins were hand-edited. The prior bc130a91 attempt failed before compilation during old simulator migration; for-dev/per-MacMini supplied and primed a replacement, which the successful run booted in 24 seconds. Failed evidence remains preserved. Meta framework debug-symbol warnings and advisory PL-6/BR3/visual/platform findings remain recorded.

The signed-in existing ForIT LLC project revealed release setup mismatches: its generated Meta app identifier differs from the inherited one in build 33; its Apple team is the old pre-March-28 value, and its selected beta was created March 20 with no users invited. Its legacy HTTPS callback host fails certificate hostname validation. Current versioned DAT1 documentation requires a matching HTTPS callback in `AppLinkURLScheme` and the portal, Associated Domains on the app, a hosted AASA file for that exact app/path, and a fresh integration beta version. Managed developer accounts cannot be beta testers: use the actual consumer Meta account paired in Meta AI, invite and accept on that account, then physically register and test.

The source follow-up uses `https://ai.forit.io/glasses/meta`, with `applinks:ai.forit.io`; for-AI owns adding only that callback path and its exact trailing slash to the existing website association, preserving Bernard’s `/chat`. The classifier compares HTTPS scheme, host, port and exact encoded path before forwarding the original URL to DAT, preserving its query and fragment. Generic HTTPS and ForIT sign-in links stay outside the Meta handler. The corresponding five new XCTest methods are **UNRUN** until the next native job. Build 33 still carries the old custom callback; its test results do not validate this follow-up.

Existing project credential alignment, portal configuration/new beta, profile capability and physical acceptance are still in progress. No new Meta account/project or guessed tester invite has been created. The [device acceptance plan](/home/runner/handoffs/OpenGlasses/ben-report-20261103/VOICE-DEVICE-ACCEPTANCE-PLAN.json) separates native tests from signed-in UI, persisted Undo, confirmed selected audio and cancellation checks. Engine publication is verified; audible selected-voice playback is not.

## Primary sources

- [Meta DAT 1.0.1 package](https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.1/Package.swift)
- [Meta DAT 1.0.1 changes](https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.1/CHANGELOG.md)
- [DAT1 iOS integration and HTTPS callback](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/)
- [DAT1 project configuration](https://wearables.developer.meta.com/docs/develop/dat/manage-projects/)
- [DAT1 release channels and tester accounts](https://wearables.developer.meta.com/docs/develop/dat/set-up-release-channels/)
- [Official voice-invocation instructions](https://github.com/facebook/meta-wearables-dat-ios/blob/main/plugins/mwdat-ios/skills/voice-invocations/SKILL.md)
- [Meta maintainer's release-channel clarification](https://github.com/meta/meta-wearables-dat-ios/discussions/326)
- [Meta supported-device FAQ](https://developers.meta.com/wearables/faq/)
- [Gen 3 support clarification](https://github.com/meta/meta-wearables-dat-ios/discussions/323#discussioncomment-18723983)
- [Camera lifecycle and microphone switching correction](https://github.com/meta/meta-wearables-dat-ios/discussions/323#discussioncomment-18984603)
- [Manufacturer store: exact RW4011 product](https://www.sunglasshut.com/us/ray-ban-meta/rw4011-8056266264771)
- [Our upstream MIT base](https://raw.githubusercontent.com/straff2002/OpenGlasses/129cfeb862818871dcdddb58c2c4c4589a3f68cc/LICENSE)
- [Pinned current upstream BSL licence](https://raw.githubusercontent.com/straff2002/OpenGlasses/8d1b9215b438317a2722950eaccaec8fa4df4318/LICENSE)
