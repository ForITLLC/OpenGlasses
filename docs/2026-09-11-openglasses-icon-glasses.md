# OpenGlasses app icon: Bernard with smart glasses

Ben, 2026-09-11 02:16Z: "Your icon is identical to 4AI. I think you need to
take this and then basically add glasses to it or something using GPT 2.5."
Follow-up to `docs/2026-09-11-forit-icons-v3.md` (WO#2014), which had made the
OpenGlasses app icon byte-identical to the for-AI-iOS one. Acceptance set by
the AoE-Commander: Bernard v3 wearing smart glasses, byte-different from the
for-AI-iOS icon, installed in the OpenGlasses app assets.

## What changed

| Site | File | Before | After |
| --- | --- | --- | --- |
| iOS app icon | `OpenGlasses/Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | `b22180042ac4c001f1ee61ede6f440a9dc031650d78d69a9e0589d8a231cf1d3` (same bytes as for-AI-iOS) | `09bf13c108069228fffe1a9936183990487404781a98d10c09703c58fc15568a` |
| Watch app icon | `DoloresWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | same as iOS | same as iOS |
| Brand source (RGBA, transparent) | `docs/brand/bernard-smart-glasses-1024.png` | — | `9270e79ec41b5153b9f82696caeb2e9ae0c61203ae053a3f622df9dce1a087a2` |
| Prompt used | `docs/brand/bernard-smart-glasses-prompt.txt` | — | — |
| README artwork pointer | `README.md` | v3 only | app icon = glasses variant, avatar = v3 |

The in-app avatar (`DoloresAvatar.imageset` on iOS, Watch and the Live Activity
widget) stays the shared v3 `bernard-forit-1024.png`
(`6161cc40ad6346773ed8d3bebbe9151a2ac26fca4d2a68885e732507a7c86fdf`). Ben's ask
was the icon on the home screen; inside the app Bernard keeps the same face as
the rest of the fleet.

## How it was made

1. **Source.** v3 `bernard-forit-1024.png` from `ForITLLC/forit-ai` `main`,
   `assets/brand-icons/source/forit-icons-v3/`, verified against `SHA256SUMS`.
2. **Model.** Azure OpenAI `gpt-image-2.5` (model version `2026-09-08`),
   deployment `gpt-image-2.5-sunburst` (GlobalStandard) on the ForIT account
   `forit-ai-image` in `rg-forit-ai-engine`. The deployment and a
   `Cognitive Services OpenAI User` role assignment for `GA_B.Thomas` were
   created for this work under the Commander's `mm_run` approval. Auth was an
   Entra bearer token; no account key was issued, and the personal OpenAI org was
   not used (ForIT product, ForIT tenant billing).
3. **Call.** `POST https://forit-ai-image.openai.azure.com/openai/v1/images/edits?api-version=preview`,
   multipart with the source PNG, `quality=high`, `size=1024x1024`,
   `background=transparent`, `output_format=png`, `n=2`. gpt-image-2.5 rejects
   `input_fidelity`. Each call used about 6k tokens and took about 55 s.
4. **Candidates.** Two prompts, two images each: A (clear lenses) and B
   (aqua-tinted lenses, camera lens on the temple). All four were shown to Ben
   flattened on `#071D2B`; B-2 was the recommendation and the one shipped.
   The shipped prompt is `docs/brand/bernard-smart-glasses-prompt.txt`.
5. **Splice.** The model re-renders the whole canvas with small drift in the
   frame and face, so the candidate was not used whole. Only the RGB inside the
   box `(272,400)-(752,600)` with a 20 px linear feather was taken from B-2;
   the alpha channel is the v3 source everywhere, and every pixel outside the
   box is the v3 source byte-for-byte. Check: the pixel diff against the v3
   source is 88,920 px, all inside x 273–750, y 401–598; alpha identical.
6. **Flatten.** The RGBA result was composited onto `#071D2B` as 8-bit RGB for
   App Store Connect (no alpha), with the same zlib-only Python as the v3 work,
   and decoded again to check it.

All image work was done with dependency-free Python (no Pillow or ImageMagick on
the fleet VM). The other three finals (A-1, A-2, B-1) were kept by the
generating session; swapping to one of them is a copy of that file into the two
`AppIcon-1024.png` slots plus a PR.

## Unchanged on purpose

- `DoloresAvatar.imageset` on all three targets (see above).
- `ForITLogo.imageset`, `LaunchImage.imageset`, asset keys, `Contents.json`
  entries, bundle ids and target names.
- The v3 source set itself; the glasses variant lives only in this repo under
  `docs/brand/`.
