# Shared source checks

This continuation uses the published Common `0.31.4` tool checkout, frozen at
`de99b5701b0287314b3e1d60ebbee495812ea16e`. `FORIT_COMMON_ROOT` must identify the
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

The existing `mini-testflight.sh` provisions its own genuine official frozen
tool checkout outside the app, then performs these steps before project
generation. It genuinely resolves packages before the first build, retains
the actual lock and passes the same tool root as an Xcode build setting. The target prebuild phases refresh the same outputs before BR-3.
Five generated Swift files and the loose PNG have explicit regular target
membership; mark generation retains `mark-auth-manifest.json`. Both Debug and
Release enable `FORIT_MARK_BRIDGE`. The standard guard command remains direct,
with no wrapper, waiver or ignored failure. Input manifests cover 27 app Swift
files, eight Watch files and eight Live Activity files after generation.

Published 0.31.4 tool source execution on October 24, 2026 accepted the Watch and
Live Activity inputs as `PASS_SOURCE_POLICY_ONLY`, including three authenticated
Controls files and two authenticated mark files per target. The app check is
`UNEVALUABLE`: this source checkout has no actual canonical `Package.resolved`.
The normal admitted workflow must resolve the real dependencies before the app
can be evaluated. A matching declaration or invented lock is insufficient.
After seven behavior-preserving explicit Combine imports, fresh 0.31.4
scanner-only diagnostics retain 29 findings around shared-menu composition,
RadialLayout/callback traversal, email arguments and native preview/attribute
qualification. These remain separate from actual app policy clearance and native
behavior; the normal resolver cannot itself clear them.

The real XcodeGen project, compiler inputs, bundled PNG, displayed controls,
accessibility and intent interactions remain unverified. The source policy binds the official frozen tool root and actual logical
resolved dependency graph. Physical compiler/cache integrity remains expressly
unmeasured; it is not a separate admission gate or receipt. The alternate
SwiftPM app route still needs maintained unconditional guard integration. None of these source checks authorizes a native run or upload.
