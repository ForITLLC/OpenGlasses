# Shared source checks

This continuation uses the published Common `0.31.5` tool checkout, frozen at
`d6f69ba013783b0aab33a8233af4a5331dd9ddc1`. `FORIT_COMMON_ROOT` must identify the
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
the actual lock, prepares fresh reports for all target/platform records before
the first report-consuming gate, and passes the same tool root as an Xcode build setting. The target prebuild phases refresh
the same outputs before BR-3.
Five generated Swift files and the loose PNG have explicit regular target
membership; mark generation retains `mark-auth-manifest.json`. Both Debug and
Release enable `FORIT_MARK_BRIDGE`. The standard guard command remains direct,
with no wrapper, waiver or ignored failure. Input manifests cover 27 app Swift
files, eight Watch files and eight Live Activity files after generation.

Published 0.31.5 tool source execution on October 24, 2026 accepted the Watch and
Live Activity inputs as `PASS_SOURCE_POLICY_ONLY`, including three authenticated
Controls files and two authenticated mark files per target.

A0's one-use `A0-OPENGLASSES0315-89E6-RESOLVE-20261024T070049Z` operation
started at 07:02:26Z on October 24 and genuinely generated the Xcode project and
resolved its dependencies. The exact retained canonical project lock has SHA256
`c9ee523cc6a80ab3306fc4f43665686cbb83e5862303a2cef09a07fd5cb92d6b`:
Common 0.31.5 at `d6f69ba0` and Meta 0.5.0 at `2ea30fa2`. Its original bytes
are tracked at the Xcode project's consumed SwiftPM location. The generic
adoption generator then returned its documented existing-bridge-proof HOLD;
that does not invalidate the successful resolver or replace this adapter.

The app-owned fixed frame and rendering-helper callback have been repaired.
`RadialLayout` measures the center and controls, preserves clockwise action order,
and uses a taller oval in constrained widths. Native preferred spacing and
measured intrinsic minima govern placement; no 340-point constant was moved.
The exact six prompts, three dispatch branches and visibility remain unchanged.
Insertion uses the existing opacity/scale timing around each action's center.

The released production guard still reports `FAIL`, now with 42 findings:
18 existing canonical/native contracts, 11 unsupported measured-layout
contracts, and 13 findings on the unchanged passive `StatusIndicator` newly
reached through that layout. These include eleven `OWN_CHROME` failures; they
are retained, not waived. Independent review confirms that the original fixed
frame and caller-rendering-switch findings are absent. A new algorithm hash
alone would not prove the passive center's role or clear these findings.

Common has supplied a private `ForITRadialActions` proposal that owns the original
ring, frame and button rendering together. Its baseline behavior mapping has
been reviewed; it is unpublished and unqualified. The next tested release's
consumer integration can remove the local layout and button helper altogether.
No private API, silent pin change or second layout qualification is adopted.
Watch and Live Activity still pass source policy.

Actual compiler inputs, bundled PNG, displayed controls, accessibility and
intent interactions remain unverified. The source policy binds the official frozen tool root and actual logical
resolved dependency graph. Physical compiler/cache integrity remains expressly
unmeasured; it is not a separate admission gate or receipt. The alternate
SwiftPM app route still needs maintained unconditional guard integration. None of these source checks authorizes a native run or upload.
