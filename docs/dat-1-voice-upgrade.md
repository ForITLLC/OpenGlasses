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

Source review, YAML/plist parsing, shell syntax and embedded Python parsing are separate from native proof. Added XCTest cases cover injected invocation acknowledgements, inert/unconfigured startup, no idle Stop recognizer, configuration isolation, catalogue requests/parsing and effective-voice audio checks. Their native execution is pending.

Commit `bc130a910a7c7d3e8215c64bde01e37cdc8f1e90` already retains the genuine Xcode-resolved canonical package lock: Meta **1.0.1 / 0bd369298eef6a980ad0bdb6c8a5502f2c02a08c** and Common **0.31.9 / 352f567e839b8faf61b6df5840c5275b016addce**. The actual November 3 job `apple-OpenGlasses-bc130a910a7c-2a5e8ae39b32` passed package resolution and retained lock bytes identical to that commit. The pins were not hand-edited; the lock SHA-256 is `377eb8e3cd13e30f0e3407633abfdbfb4001c2cf10d7dad3e7845f063b22293c`.

That job ran from 03:23:44 to 03:49:02 UTC and exited 1 when the owned iPhone simulator's first boot failed to finish its data migration. It stopped before app compilation, tests, signing, archive, export or upload. Resolving the SDK does not prove the compiler can consume its Swift 6.3.3 interfaces. The [independent native result review](/home/runner/handoffs/OpenGlasses/ben-report-20261103/NATIVE-INDEPENDENT-RESULT-REVIEW.json) binds the exact source, raw lock, failure and cleanup receipts; the [actual job result](/home/runner/handoffs/OpenGlasses/ben-report-20261103/native-jobs/apple-OpenGlasses-bc130a910a7c-2a5e8ae39b32/result.json) records the failed execution.

No new TestFlight upload or working physical Meta launch or selected-voice playback is claimed. Existing build 1.0 (32) and old screenshot evidence retain their original source identity. The [voice device acceptance plan](/home/runner/handoffs/OpenGlasses/ben-report-20261103/VOICE-DEVICE-ACCEPTANCE-PLAN.json) separates existing contract tests from the unrun signed-in UI, persisted Undo, confirmed audio and cancellation checks; it uses ordinary app requests coordinated with for-AI, without duplicate standalone provider probes.

## Primary sources

- [Meta DAT 1.0.1 package](https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.1/Package.swift)
- [Meta DAT 1.0.1 changes](https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.1/CHANGELOG.md)
- [Official voice-invocation instructions](https://github.com/facebook/meta-wearables-dat-ios/blob/main/plugins/mwdat-ios/skills/voice-invocations/SKILL.md)
- [Meta maintainer's release-channel clarification](https://github.com/meta/meta-wearables-dat-ios/discussions/326)
- [Meta supported-device FAQ](https://developers.meta.com/wearables/faq/)
- [Gen 3 support clarification](https://github.com/meta/meta-wearables-dat-ios/discussions/323#discussioncomment-18723983)
- [Camera lifecycle and microphone switching correction](https://github.com/meta/meta-wearables-dat-ios/discussions/323#discussioncomment-18984603)
- [Manufacturer store: exact RW4011 product](https://www.sunglasshut.com/us/ray-ban-meta/rw4011-8056266264771)
- [Our upstream MIT base](https://raw.githubusercontent.com/straff2002/OpenGlasses/129cfeb862818871dcdddb58c2c4c4589a3f68cc/LICENSE)
- [Pinned current upstream BSL licence](https://raw.githubusercontent.com/straff2002/OpenGlasses/8d1b9215b438317a2722950eaccaec8fa4df4318/LICENSE)
