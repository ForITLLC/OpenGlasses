# OpenGlasses shared control guard integration (source draft)

This is the isolated shared-controls source task. It does not release the app or
satisfy the native capture/build hold. Common remains pinned to the tested
`0.17.1` baseline in `project.yml` and `Package.swift`; candidate role APIs and
the build guard have not been admitted as a tested dependency release. The
current display name is Bernard Glasses. Logical ForIT Glasses naming and other
whole-app conformance gaps are separate work.

## Mandatory per-target command

Each shipping XcodeGen target has an unconditional `preBuildScripts` command
with `basedOnDependencyAnalysis: false`. The command uses `exec` so a missing
shared tool, unknown syntax, missing input, or policy finding fails the build.
There is no wrapper, copied guard, waiver, warning mode, or fallback tool.

The maintained build owner must provision and freeze a trusted official
`ForITLLC/for-iCommon` tool checkout and export `FORIT_COMMON_ROOT` to its root.
The entry point is `Scripts/control-guard/control_guard.py`, invoked with
`/usr/bin/python3 -I`. An arbitrary developer checkout or app-owned copy does
not establish admission. The source draft intentionally cannot make a missing
external tool succeed. Provisioning and freezing that tool is an upstream
blocker; setting the variable alone does not prove its authenticity. The
maintained conformance gate must run from that same admitted checkout.

The candidate parser permits the literal tool environment variable only; the
inputs and report paths are explicit. Each `forit-app.json` build record and its
XcodeGen command use the same exact pair:

| Target / platform | Input manifest | Report |
| --- | --- | --- |
| OpenGlasses / iOS | `Config/ControlGuard/OpenGlasses-iOS-inputs.json` | `/tmp/forit-openglasses-shared-controls-OpenGlasses-iOS-br3.json` |
| DoloresWatch / watchOS | `Config/ControlGuard/DoloresWatch-watchOS-inputs.json` | `/tmp/forit-openglasses-shared-controls-DoloresWatch-watchOS-br3.json` |
| GlassesActivityWidget / iOS | `Config/ControlGuard/GlassesActivityWidget-iOS-inputs.json` | `/tmp/forit-openglasses-shared-controls-GlassesActivityWidget-iOS-br3.json` |

`/tmp` already exists on the runner and leaves reports outside a clean source
checkout. The maintained runner must retain these reports with its other build
artifacts, run the gate before another build of the same branch overwrites them,
and reject missing/stale reports. These branch-scoped report paths are not
release evidence by themselves. No reports are checked in.

## Compile membership and deployment floors

The manifest root is `../..`, relative to each manifest. The phone enumerates
all Swift files under the XcodeGen source root `OpenGlasses/Sources`; the Watch
enumerates `DoloresWatch`; the Activity extension enumerates its two own Swift
files plus `OpenGlasses/Sources/Models/GlassesActivityAttributes.swift`, which
is explicitly compiled into both phone and extension, and the explicit DEBUG
fixture/preview files `TestSupport/LiveActivity/GlassesActivityFixtures.swift`
and `TestSupport/LiveActivity/GlassesActivityWidgetPreviews.swift`. The separate
`GlassesActivityFixtureSession.swift` future host adapter is excluded from both
widget and phone compile membership. Resource assets and
optional Secrets.plist are not Swift compile inputs. Unit-test target sources
are separate; any DEBUG fixture compiled into a shipping target must be listed
even when its release conditional branch is empty. Update these explicit lists
whenever shipping compile membership changes; the shared source-graph/gate
comparison must reject omissions or extra inputs.

No platform or device setting changed: phone and Activity extension inherit
iOS 26.0 from project options; Watch explicitly uses watchOS 11.0. Watch has no
ForITCommon package dependency in the baseline. No generated bridge is used;
`bridges` is empty and `commonRevision` is deliberately absent. An eventual
bridge requires a separately admitted immutable Common revision, canonical
export manifest, all generated compiled sources, and shared-tool verification.

## Provisional upstream contract and blockers

Read-only candidate checkout observed at
`/home/runner/orca/workspaces/for-iCommon/shared-control-audit`, HEAD
`008f8c39c6603ac4fec8c2076f8cc10be66c6552`, with uncommitted parser/role work.
This moving checkout is a contract reference, not a production provision or
released dependency. The README contract SHA256 observed on 2026-10-18 was
`98e001cec6a470d4bfb01043b9faf499f27ac60990f45f70982021ffbdde9797`.
Other observed working-file hashes:

| File | SHA256 |
| --- | --- |
| `Scripts/control-guard/control_guard.py` | `58c8bd1858f4b90d794f4e68568b7cbf778ded30166021ca293c1e17cdd49faf` |
| `Scripts/control-guard/source_graph.py` | `b59ad78d0719678a905e211f8fb945d19b4cace47ea3c1e242089c8a37a02499` |
| `Scripts/forit-gate/forit-gate.py` | `c9be7ef222eed0d8ff763dbfddfb306f630d116ab2fcca07cc4d179c927264fd` |

The candidate source graph currently fails on the phone's absent optional
`OpenGlasses/Secrets.plist` resource before filtering non-compile resources.
The existing `optional: true` / `buildPhase: resources` declaration is retained;
the parser needs reviewed support rather than a fake secret or source omission.
Watch and Activity source membership can be compared with that candidate.
The candidate gate also warns that `controlGuard` is an unknown configuration
key; upstream schema documentation/recognition remains pending. This scoped
`forit-app.json` does not claim completion of unrelated conformance declarations.

Local JSON/YAML parsing, literal phase/path comparison, source enumeration, and
missing-tool failure are static source checks. All three missing-tool shell
checks exited 2. A successful negative check is not a guard PASS.

The unreleased candidate CLI was also executed once per manifest using
`/usr/bin/python3 -I -B`. Tool implementation hashes were identical before and
after the three executions. The phone has 26 sources and returned UNEVALUABLE
with one optional Secrets.plist source-graph diagnostic. Watch has 3 sources
and returned FAIL with three OWN_CHROME findings (padding, background, corner
radius). Activity has 5 sources, including both whole-file DEBUG fixtures, and
returned FAIL with two OWN_CHROME findings (padding, background) and one
OWN_STYLE finding (plain style outside proven native context). The separate
future fixture-host source is excluded. These are candidate source-policy
results, not production BR-3 or native validation. Raw reports and command/hash
evidence are retained outside the repository under
`/home/runner/handoffs/OpenGlasses/shared-control-audit-20261018/validation-source`.

The production guard/gate remains blocked on the supported released tool,
parser support, and remaining source-policy failures. The reviewed role release
must support these targets at unchanged floors. XcodeGen generation, generated
project phase verification, native
compilation, Watch/Activity interaction and accessibility tests, and original
screenshots remain pending fresh authorization and upstream admission. No Mini,
native execution, build slots, release, or upload was used for this source draft.
