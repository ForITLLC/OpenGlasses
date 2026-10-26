# Shared source checks

Current policy (October 26, Ben's ship-all instruction, A0 handoff
`ff155c9db230`): BR-3 and Dark/Light/VS-1 findings are advisory at this app's
build/release boundary. A0 is retired; the owning lane uses its normal workflow
and published Common 0.31.9, released October 26 at 02:44:30Z.
The three unconditional BR-3 phases keep the original JSON reports and write
the guard's actual status beside each report as `.exit-code`; Xcode diagnostics
are printed as warnings and the advisory phases return zero. Compiler, signing,
export and upload command failures remain failures. This changes the app's
handling of findings, not Common's checker, findings or historical results.

Current source selects Common `0.31.9` at
`352f567e839b8faf61b6df5840c5275b016addce`, annotated tag
`9050f4a1ce99d023e3a550ffc74f338a135d1d6c`. The normal SDK resolver produced the actual tracked 0.31.9 lock, SHA256
`3304423f61d0c59db9490a93e5ed07a535640e9792f2f5278f242f71a4541638`,
in run `forit-openglasses-release-20261026T0251Z`. Common is exact `352f567e`
and Meta remains 0.5.0/`2ea30fa2`; no lock was edited by hand. Native build
and TestFlight results remain pending.

The earlier admission and blocking-policy descriptions below are historical.

The previous continuation selected published Common `0.31.7`, frozen at
`927a394b803c7c425517e35b532d44037fc279d9`, annotated tag object
`f0880ddf36b6445399cae9653dfbd95f7a4a028c`. `FORIT_COMMON_ROOT` must identify
the maintained official checkout. A caller-edited origin or fabricated lock
cannot supply that authority.

The previous canonical project lock was actual output from A0's admitted 0.31.7
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
Release enable `FORIT_MARK_BRIDGE`. The guard stays direct and always runs;
its findings and original exit code are retained under the current advisory policy. The app input list follows actual source membership
after removal of the local layout. Watch and Live Activity each have eight Swift
inputs after generation.

The canonical `ForITRadialActions` package component owns the original 340-point
ring, placements and button rendering. The app supplies the same ordered action
data and async dispatch, preserving prompt/photo/photoThen branches, visibility
and whole-ring opacity/scale transition. The local measured-layout prototype
and button renderer are removed with the layout's compile-input entry. This
adopts the shared baseline ring; it does not claim adaptive narrow-width or
large-type behavior. Actual layout, target containment and AX remain unverified.

The October 26 caller repair places the unchanged mixed `GeometryReader` canvas
directly inside `NavigationStack`. This removes the extracted computed-view
alias that the guard classified as a control. The released 0.31.7 production
check drops from 27 findings, including 18 `OWN_CHROME`, to seven unresolved
native/shared rendering contracts and zero `OWN_*`. All artwork, layout
margins, viewport minimum, button styles, actions and transitions are retained.
The existing feedback extension remains unchanged; its inherited native
`View.modifier` lookup is unresolved and is not claimed as a policy pass.

Watch retains two unresolved avatar image modifiers, `.resizable()` and
`.scaledToFit()`, and Live Activity passes source policy. Remaining Common
contracts include named image effects, nested shared radial recognition,
native `scrollBounceBehavior` and inherited `View.modifier` lookup. No target,
Preview, artwork, modifier or diagnostic is excluded to clear policy.

Common 0.31.9 is now published and selected. The owning lane runs genuine
SDK resolution through the maintained helper and retains its actual lock.
The old A0 allocation prerequisite is retired.

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
