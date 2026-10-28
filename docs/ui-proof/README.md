# iOS canonical-mark proof tests

The `OpenGlasses-VisualProof` shared scheme selects the maintained
`OpenGlassesUITests` iOS UI-test bundle. It exercises the actual app's existing
Debug screenshot fixtures. The ordinary `OpenGlasses` unit-test scheme and
release helper keep their existing unit-test selection.

This source preparation follows Common message `msg_30b47b920fc7`. It does not
run native tests or supply an execution grant. Schedule native work through
for-dev's existing SERIAL queue and normal lane/resource controls. No A0 or
Common ACK gate, controller or scheduler is introduced.

## Exact dependency and shipment identities

The dependency is released **0.31.9**, commit
`352f567e839b8faf61b6df5840c5275b016addce`, annotated tag
`9050f4a1ce99d023e3a550ffc74f338a135d1d6c`.
It is not 0.31.19. Both app manifests, authenticated Watch/activity exports,
source guard revision and helper agree. The genuine canonical project lock
has SHA256 `3304423f61d0c59db9490a93e5ed07a535640e9792f2f5278f242f71a4541638`;
Meta stays 0.5.0 at `2ea30fa228359315baf71c404aec821472e994c1`.
No unpublished candidate is adopted by this change.

Shipped iOS **1.0 (32)** remains bound to app source
`0347d5434120bcc9a8e2947d754d3039f3adff43`. Apple's uploadedDate is
2026-10-26 03:04:43Z; the retained 03:06:18Z readback confirms VALID and
IN_BETA_TESTING for ForIT Internal. A new source-bound Debug proof build is a
separate identity, commonly 1.0 (1); read its actual bundle values. Neither
that build nor the historical 0.17.1 before frames may be labelled build 32.

## Stable test identifiers

The test class is `OpenGlassesUITests/OpenGlassesVisualProofTests`:

- `testFixtureScenesRequestedLightStandard`
- `testFixtureScenesRequestedDarkStandard`
- `testFixtureScenesRequestedLightAX5`
- `testFixtureScenesRequestedDarkAX5`
- `testProfilePanelRequestedLightStandardAndAX5`
- `testProfilePanelRequestedDarkStandardAndAX5`

Each fixture method attaches the five configured scenes. Each panel method
launches home and taps the actual shared profile control once for standard
text and once for AX5. That is 24 named screenshots and 24 text context
attachments per destination if all scenarios complete. An attachment count is
not a pass verdict. Use the exact returned result/test identifiers for export;
nested activity names and requested-look attachment names identify each cell.

## Native invocation contract

On the admitted executor, use a genuine clean checkout of the exact reviewed
app commit. Keep a job-owned official Common checkout at the revision above;
authenticate the tag and exporter bytes using `prepare-shared-bridges.py`,
generate both package-free targets before XcodeGen, and resolve the actual SDK
packages with the existing canonical lock. Use that same `FORIT_COMMON_ROOT`
as environment and Xcode build setting. Preserve actual Sources/Resources,
normal sandbox/signing checks, and real compiler/test errors.

The consuming test command has this shape (substitute the executor's actual
owned destination and output path before queue admission):

```sh
/Users/Shared/ci-sim/ci-sim-lane.sh --lane OpenGlasses xcodebuild test \
  -jobs 2 -project OpenGlasses.xcodeproj -scheme OpenGlasses-VisualProof \
  -configuration Debug -destination "id=$OWNED_UDID" \
  -only-testing:OpenGlassesUITests \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath "$PROOF_OUTPUT/DerivedData" \
  -resultBundlePath "$PROOF_OUTPUT/VisualProof.xcresult" \
  -clonedSourcePackagesDirPath build/spm -scmProvider system \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  FORIT_COMMON_ROOT="$FORIT_COMMON_ROOT" CODE_SIGNING_ALLOWED=NO
```

Run one owned iPhone or iPad destination at a time, through the current SERIAL
resource route. Verify current lane allocation before boot; never borrow or
create a device. For requested system light/dark capture, set the owned
simulator appearance using its maintained lane `simctl ui` route and select
only the matching explicit light/dark method IDs. Restore the original state
and shut down only the simulator this run owns. Missing devices remain gaps.

Inspect installed `xcresulttool help export attachments` (or its advertised
attachment-export equivalent) before export; record the exact supported command
and real test identifier. Retain each original attachment's path, name and own
PNG SHA256, together with its actual `.xcresult`, test ID, app commit/tree,
compiled bundle version/build, resolved lock and Common revision, device/runtime,
requested appearance/size and observed verdict. The canonical raw asset digest
`c885ca50c30f5a4fcf55cb8f083d055831ed8878aff39b9fb782bd05a104edd8`
is not a rendered screenshot hash.

## What these tests can establish

The tests launch five existing fixture scenes and open the real shared profile
panel with accessibility identifiers. They preserve original XCTest screenshot
attachments and assert the expected scene/panel appears. Actual compilation,
UI execution, screenshots, contrast/geometry and native AX/action verdicts are
UNRUN until the admitted job returns its evidence. Passing a scene assertion
alone does not establish visual acceptance.

Requested system light appearance is not proof of a light app surface:
MainView, SettingsView and LaunchScreen deliberately prefer dark. Existing
product presentation is preserved. Review each original PNG and report forced
dark or other observed limits honestly. AX5 requests likewise need observation.

The existing fixtures suppress SDK, listeners, permission requests and service
actions. A panel tap can establish that the real panel opens; these tests do not
validate the six hardware/AI action callbacks, sign-in, feedback sends or device
permissions. No persisted credentials or live service action should be changed.
Source assertions and captured fixtures are not installed-user or hardware proof.

This initial iOS target supplies no native Mac/Vision/Watch test target,
WidgetKit compositor view, SpringBoard installed icon, split-view/resize proof
or Ben install/open confirmation. Those missing surfaces stay explicit; the
five existing lapel assets and six radial actions retain their source identities.
