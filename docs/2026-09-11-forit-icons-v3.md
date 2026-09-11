# ForIT v3 brand icons (WO#2014)

Ben, 2026-09-11: "ForIT-Dolores-Bernard-Icons use this … you know all the places
these need to go." Source of truth is `ForITLLC/forit-ai` `main`,
`assets/brand-icons/source/forit-icons-v3/` (18 files). The whole set was pulled
from GitHub and checked with `sha256sum -c SHA256SUMS`: 18 of 18 OK. Per the
set's `README.txt` the icons are transparent RGBA on a shared hex frame in the
measured brand colours navy `#142F43` and aqua `#8EDCEF`. No artwork was
generated here.

Replaces the v2 portrait from `docs/2026-09-10-bernard-v2-artwork.md`. Same
treatment as v2 and as `for-AI-iOS` PR #29: image sets keep the source bytes and
transparency; Apple app icons are the same source composited onto `#071D2B` as
8-bit RGB because App Store Connect rejects icons with an alpha channel. The
flatten was done with a zlib-only Python script (no Pillow or ImageMagick on the
fleet VM) and decoded again to check it; it is byte-identical to the
`for-AI-iOS` AppIcon, so every ForIT native app ships the same icon file.

## Sites switched

| Site | File | Treatment | SHA-256 |
| --- | --- | --- | --- |
| iOS app icon | `OpenGlasses/Sources/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | `bernard-forit-1024.png` on `#071D2B`, RGB | `b22180042ac4c001f1ee61ede6f440a9dc031650d78d69a9e0589d8a231cf1d3` |
| Watch app icon | `DoloresWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | same file as iOS | `b22180042ac4c001f1ee61ede6f440a9dc031650d78d69a9e0589d8a231cf1d3` |
| In-app avatar (launch, onboarding, status) | `OpenGlasses/Sources/Resources/Assets.xcassets/DoloresAvatar.imageset/dolores-avatar.png` | `bernard-forit-1024.png` byte-for-byte | `6161cc40ad6346773ed8d3bebbe9151a2ac26fca4d2a68885e732507a7c86fdf` |
| Watch avatar | `DoloresWatch/Assets.xcassets/DoloresAvatar.imageset/dolores-avatar.png` | same | `6161cc40ad6346773ed8d3bebbe9151a2ac26fca4d2a68885e732507a7c86fdf` |
| Live Activity bundle avatar | `GlassesActivityWidget/Assets.xcassets/DoloresAvatar.imageset/dolores-avatar.png` | same | `6161cc40ad6346773ed8d3bebbe9151a2ac26fca4d2a68885e732507a7c86fdf` |
| README artwork pointer | `README.md` | points at the v3 source | — |

The Watch `AppIcon.appiconset/Contents.json` previously listed legacy per-size
slots with no `filename`, so the 1024 file it held was never wired. It now uses
the Xcode 14+ single-size entry (`universal` / `watchos` / `1024x1024`).

The in-app views clip the avatar to a circle with an aqua ring. The hex's six
corners all sit inside the bounding circle, so the frame renders intact; no
Swift changes were needed.

## Unchanged on purpose

- `ForITLogo.imageset` is the ForIT wordmark (hex + "ForIT / Forward-looking
  IT", rendered as a tinted template). v3 ships only `forit-symbol.png` (the
  two-part cube glyph, 416×467) and no wordmark, so there is nothing to switch.
- `LaunchImage.imageset` is not brand artwork and is not referenced by code.
- Dolores v3 art is the for-Dolores hand-off; this app is Bernard's and renders
  no Dolores icon.
- Bundle ids, the `DoloresAvatar` / `AppIcon` asset keys, target names and
  persistence identifiers.
- Maeve (`forit-ai` `54e11df`, `assets/brand-icons/source/maeve-v1/`) is the
  internal Teams Support agent. OpenGlasses renders Bernard only and has no
  Maeve site (`git grep -i maeve`: 0 hits outside this line); any engine agent
  avatar would come from the API `iconUrl`, so no bundled asset is needed.
