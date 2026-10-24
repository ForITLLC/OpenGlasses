# Shared source checks

This continuation selects published Common `0.31.7`, frozen at
`927a394b803c7c425517e35b532d44037fc279d9`, annotated tag object
`f0880ddf36b6445399cae9653dfbd95f7a4a028c`. `FORIT_COMMON_ROOT` must identify
the maintained official checkout. A caller-edited origin or fabricated lock
cannot supply that authority.

The tracked canonical project lock is actual output from A0's admitted 0.31.7
SDK resolver, SHA256
`ba497973e9c247ff908fb3364e51141b0adc791bbcde1ece92344b429aeda851`.
It binds Common 0.31.7 at `927a394b` and retains Meta 0.5.0 at `2ea30fa2`.
The earlier genuine 0.31.5 lock `c9ee523c` remains preserved externally.
Only the returned canonical bytes are applied; no resolver pins are synthesized.
Current source reports must be regenerated after this owner commit. Actual
resolution is not app source-policy or native acceptance.

Every shipping target has an unconditional precompile phase with an explicit
input/report pair in `forit-app.json`. The app links the full package. Watch and
Live Activity compile the separately authenticated mark and Controls exports;
they never link the full package or copy its renderer into this repository.

Before XcodeGen, generate required files into ignored build output:

```sh
python3 -I -B Scripts/prepare-shared-bridges.py --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/DoloresWatch"
python3 -I -B Scripts/prepare-shared-bridges.py --source "$FORIT_COMMON_ROOT" --output "$PWD/.build/forit-bridges/GlassesActivityWidget"
```

The existing `mini-testflight.sh` provisions its job-owned genuine official
frozen checkout and exports these inputs before XcodeGen. It genuinely resolves
packages, retains the actual lock, and prepares fresh reports for every configured
target/platform before the first report-consuming gate. The same tool root is
passed as an Xcode build setting. Unconditional target phases repeat exports and
source checks before compilation. Existing signing and admission behavior stays
unchanged.

Five generated Swift files and the loose PNG retain explicit regular target
membership; mark generation retains `mark-auth-manifest.json`. Both Debug and
Release enable `FORIT_MARK_BRIDGE`. The guard stays direct, with no wrapper,
waiver or ignored failure. The app input list follows actual source membership
after removal of the local layout. Watch and Live Activity each have eight Swift
inputs after generation.

The canonical `ForITRadialActions` package component owns the original 340-point
ring, placements and button rendering. The app supplies the same ordered action
data and async dispatch, preserving prompt/photo/photoThen branches, visibility
and whole-ring opacity/scale transition. The local measured-layout prototype
and button renderer are removed with the layout's compile-input entry. This
adopts the shared baseline ring; it does not claim adaptive narrow-width or
large-type behavior. Actual layout, target containment and AX remain unverified.

Pre-resolution 0.31.7 checks with regenerated authenticated bridges accepted Live
Activity source policy and refused the then-stale app lock. Watch fails on the unchanged
named avatar image's `.resizable()` and `.scaledToFit()` modifiers in
`DoloresWatchView.swift`; both findings are retained for producer review.
No target is dropped and no artwork or modifier is removed to clear policy.

A0's `A0-OPENGLASSES0317-RESOLVE-20261024T185222Z` operation started at
18:53:16Z and ended at 18:53:22Z on October 24. Xcode resolved the real package
graph and its actual SDK checkout was verified. The combined operation retained
exit code 1 and `resolverScopePass: false` because final generic BR-3 staging
held on the existing bridge proof. Its accepted END has no closure debt; its
one-use grant is permanently spent and grants no compile, test or upload.
The documented owner review retains the authenticated manifests and exact
target integration; it does not delete proof, rerun staging or rewrite that END.
A0's exporter logs passed, but raw Mini bridge bytes were not independently
retained. Local source proof is not actual compiler or bundle closure.

Historical evidence remains bounded. Published 0.31.5 source checks accepted
Watch and Live Activity as `PASS_SOURCE_POLICY_ONLY`. The one-use operation
`A0-OPENGLASSES0315-89E6-RESOLVE-20261024T070049Z` started at 07:02:26Z on
October 24, generated the real project and resolved Common 0.31.5 at `d6f69ba0`
and Meta 0.5.0 at `2ea30fa2`. Generic staging then returned its documented
existing-bridge-proof HOLD; the original local body exit code remains 1. A0
closure evidence is recorded separately and grants no successor run. That lock
and those reports do not validate 0.31.7.

The 0.31.5 phone baseline had 29 findings. Its later measured-layout prototype
had 42: 18 prior canonical/native contracts, 11 unsupported layout contracts and
13 unchanged passive-center findings. These are historical snapshots, not
current 0.31.7 findings or clearance. Regenerate current results from the exact
tool, actual resolved lock and final source.

Follow the [published adoption recipe](https://github.com/ForITLLC/for-iCommon/blob/0.31.7/Scripts/control-guard/README.md#adoption-recipe-one-source-graph-real-resolution-then-reports).
Preserve and review existing bridge proofs if generic staging holds. If a normal
mixed SwiftPM/Xcode workflow produces multiple recognized locks, retain every
genuine input and resolve Common disagreements through that workflow. Do not
copy or delete locks to manufacture agreement.

Actual compiler inputs, bundled PNG, controls, accessibility and intent behavior
remain unverified. Physical compiler/cache integrity remains expressly unmeasured;
it is not a separate admission gate or receipt. The alternate SwiftPM app route
still needs maintained unconditional guard integration. None of these source
checks authorizes native execution or upload.
