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

The November 4 source follow-up corrects the connection indicator and Meta launch-error presentation. Registration no longer claims a physical link; current service errors reach the existing error display without clearing unrelated errors or overwriting newer errors after an old acknowledgement. Nine production-path regression tests are added but **not yet run**. This source follow-up needs a native qualification and replacement binary; it is not part of shipped build 35. It reuses the existing controls and adds no setup step. [Defect record](https://issues.forit.io/issues/73D78448-A5CF-4041-AAF3-BF2B97E5C9D0).

The latest qualified native app is **ForIT Glasses 1.0 (35)**, from exact source `7e19f3f2175067aa8b3f0d6aa9fa7503b9bd480b`. The November 3 maintained Mini job `apple-OpenGlasses-7e19f3f21750-ab358a351dbf` passed all **107 tests**, signing, archive/export checks, one upload and cleanup; it ended at 07:14:22 UTC with exit 0. The exported app's actual signature includes `applinks:ai.forit.io`. Apple readback at November 3 18:08 UTC confirmed VALID, unexpired, INTERNAL_ONLY and IN_BETA_TESTING. See the [native release review](/home/runner/handoffs/OpenGlasses/ben-report-20261103/BUILD35-FINAL-NATIVE-REVIEW.json) and [Apple readback](/home/runner/handoffs/OpenGlasses/ben-report-20261103/APPLE35-RESUME-1808-READBACK.json). This is release evidence, not proof that Ben installed or opened it.

The genuine 685-byte package lock, tested and archived copies match: Meta **1.0.1 / 0bd369298eef6a980ad0bdb6c8a5502f2c02a08c**, Common **0.31.9 / 352f567e839b8faf61b6df5840c5275b016addce**, SHA256 `377eb8e3cd13e30f0e3407633abfdbfb4001c2cf10d7dad3e7845f063b22293c`. No pins were hand-edited. The earlier `bc130a91` attempt failed before compilation during old simulator migration; for-dev/per-MacMini supplied and primed a replacement. The old simulator remains preserved and shut down; the maintained workflow now selects the working replacement. Failed evidence remains preserved. Meta framework debug-symbol warnings and advisory PL-6/BR3/visual/platform findings remain recorded.

Build 33 used the inherited custom callback. Build 34 passed 107 tests and uploaded, but its actual signature exposed an empty entitlements dictionary: XcodeGen's path-only specification regenerated the file without the required domain. Build 35 corrected `entitlements.properties`, then independently verified the signed domain after archive/export. That replacement archive is complete; the earlier defect and failed snapshots are historical evidence, not a current build prerequisite.

The source uses Meta application ID `25955189420829430` and `https://ai.forit.io/glasses/meta`, with `applinks:ai.forit.io`. The classifier compares HTTPS scheme, host, port and exact encoded path before forwarding the original URL to DAT, preserving its query and fragment. Generic HTTPS and ForIT sign-in links stay outside the Meta handler. for-AI published the hosted association for this exact app and both callback paths, retaining Bernard's `/chat` entries. A fresh public read on November 4 at 18:31 UTC confirmed the AASA response and canonical callback return HTTP 200; the trailing slash redirects to the canonical path with HTTP 308. The canonical callback retains `no-store` and `no-referrer`. See the [public readback](/home/runner/handoffs/OpenGlasses/ben-report-20261103/PUBLIC-CALLBACK-READINESS-20261104.json). This does not establish the installed phone's cached association or callback behavior.

The existing ForIT LLC Meta project's developer sign-in succeeded on November 3. Its saved Apple team is `UUSSWWML2A`, bundle `com.forit.openglasses.dolores`, HTTPS callback `https://ai.forit.io/glasses/meta`, and project and product-listing name **ForIT Glasses**. One fresh Meta integration version **1.0.0** became Ready and was assigned to the existing private Beta channel; a fresh navigation verified that selection at 19:10 UTC, and a visible readback at 19:19 showed zero invited users. Its frozen Project data matched the identifiers above. This Meta integration version is separate from native app build 35. These are retained portal observations, not a new authenticated portal read today. See the [setup journal](/home/runner/handoffs/OpenGlasses/ben-report-20261103/META-LIVE-1846-SETUP-JOURNAL.json).

The remaining enrollment step is to observe the actual consumer Meta account in Meta AI on Ben's paired phone, invite that exact existing account, accept its Beta invitation and register the app. A managed developer login, purchase receipt or historical account notice does not establish the currently paired identity. No guessed tester invite or new Meta account/project has been created.

Physical acceptance remains open: Ben's build-35 installation/opening, real registration and locked-phone “Hey Meta” launch, available authenticated voice choices, audible matching selected voice, Undo and persistence, Stop/follow-up and camera/microphone recovery have not been proved. The [device acceptance plan](/home/runner/handoffs/OpenGlasses/ben-report-20261103/VOICE-DEVICE-ACCEPTANCE-PLAN.json) and [source-checked operator steps](/home/runner/handoffs/OpenGlasses/ben-report-20261103/PHYSICAL-ACCEPTANCE-SIX-STEPS.json) retain those checks. Engine publication is verified; actual selected-voice playback is not. Documentation-only changes do not require a replacement native build.

The existing [glasses work record](https://tasks.forit.io/?task=54FED5E9-BEE9-42F5-854C-FB569A06A810) retains Ben's request and on-device definition of done. No physical check is marked passed from source, simulator or portal evidence alone.

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
