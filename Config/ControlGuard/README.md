# Shared source checks

This continuation uses the published Common `0.31.3` tool checkout, frozen at
`31a62ae9eab7e822cfac327a6bf3d0fcf8c12e50`. `FORIT_COMMON_ROOT` must identify the
maintained official checkout. Neither a caller-edited origin nor a fabricated
`Package.resolved` supplies that authority.

Every shipping target has an unconditional precompile phase with an explicit
input/report pair in `forit-app.json`. The app links the full package. Watch and
Live Activity compile the separately authenticated mark and Controls exports;
they never link the full package or copy its renderer into this repository.

Before XcodeGen, generate the required files into ignored build output:

```sh
python3 -I -B Scripts/prepare-shared-bridges.py --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/DoloresWatch"
python3 -I -B Scripts/prepare-shared-bridges.py --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/GlassesActivityWidget"
```

The existing `mini-testflight.sh` performs these two steps before project
generation. The target prebuild phases refresh the same outputs before BR-3.
Five generated Swift files and the loose PNG have explicit regular target
membership; mark generation retains `mark-auth-manifest.json`. Both Debug and
Release enable `FORIT_MARK_BRIDGE`. The standard guard command remains direct,
with no wrapper, waiver or ignored failure. Input manifests cover 27 app Swift
files, eight Watch files and eight Live Activity files after generation.

Published-tool source execution on October 23, 2026 accepted the Watch and
Live Activity inputs as `PASS_SOURCE_POLICY_ONLY`, including three authenticated
Controls files and two authenticated mark files per target. The app check is
`UNEVALUABLE`: this source checkout has no actual canonical `Package.resolved`.
The normal admitted workflow must resolve the real dependencies before the app
can be evaluated. A matching declaration or invented lock is insufficient.
Scanner-only diagnostics additionally hold the existing shared-menu composition,
RadialLayout traversal and email keyboard/content-type arguments for maintained
adapter qualification. These findings remain separate from actual app policy
clearance and native behavior.

The real XcodeGen project, compiler inputs, bundled PNG, displayed controls,
accessibility and intent interactions remain unverified. A separate official
tool checkout also does not establish byte-level provenance for a different
compiled SwiftPM cache; that existing Common collector gap remains upstream.
The alternate SwiftPM app route still needs maintained unconditional guard
integration. None of these source checks authorizes a native run or upload.
