# Live Activity control regression preparation

SOURCE ONLY, 2026-10-18, task 8EDA0A3E. Baseline source:
`45b52531d64f8673429bf7131653b53b65f31470`. No SDK compile, preview, native
test, simulator, device, Mini slot, upload or screenshot ran in this task.
Common's widget control role is unreleased; adoption remains blocked. These
files do not supply app-owned replacement chrome or set a fleet radius.

## Reusable source and integration

`TestSupport/LiveActivity/GlassesActivityFixtures.swift` supplies six fixed
ContentStates matching the current app vocabulary: disconnected, ready,
listening, processing, speaking and an 80-Character long response. Its
`expectedStatusSymbol` is an assertion oracle for review, not rendering code.
No time, network, preferences, hardware, AppState or Activity request is read.

`GlassesActivityWidgetPreviews.swift` instantiates the production
`GlassesActivityWidget` in four actual ActivityConfiguration presentations:
Lock Screen content and Dynamic Island expanded, compact and minimal. Each
macro supplies all six states. These are **Live Activity presentations**, not
Home Screen widget families. There is no supportedFamilies Home Screen widget
in this source. Preview API:
[Apple's ActivityConfiguration preview macro](https://developer.apple.com/documentation/widgetkit/preview(_:as:using:widget:contentstates:))
and [ActivityPreviewViewKind](https://developer.apple.com/documentation/widgetkit/activitypreviewviewkind).

The files deliberately sit outside the `GlassesActivityWidget` sources glob.
`project.yml` explicitly includes the fixture and preview files in the widget
target for future approved Xcode preview use. Both are DEBUG-only;
do not include the preview file in the app/unit-test module, where
GlassesActivityWidget is unavailable. The separate project-wiring change
includes only these first two files, with no dependency adoption. Type
checking remains pending an authorized SDK pass.

`GlassesActivityFixtureSession.swift` is optional request/update/end source
for a **separate minimal fixture host**, gated by both DEBUG and
`LIVE_ACTIVITY_FIXTURE_HOST`. Compile it with the attributes and fixture file;
embed the real widget extension; give the host `NSSupportsLiveActivities=true`.
Do not instantiate the shipping AppState or its hardware/permission services.
Call `try await session.show(GlassesActivityFixtures.listening)` from a
foreground host, then `show` for subsequent cases and `await session.end()`
on cleanup. It ends only its own activity. It supplies no production entry
point, launch argument, automatic task or native authorization.

There is no current shipping launch hook for these six widget states. The
app's existing screenshot-scene hook does not drive the extension. A future
approved UI harness should map a validated fixture ID from its own launch
arguments to `GlassesActivityFixtures.all` and invoke the session above;
unknown IDs must fail setup. Keep that host outside shipping sources. Minimal
Island presentation requires another controlled Live Activity so the system
can allocate the two-activity layout; record that second activity separately
and clean up only fixture-owned activities. Do not relabel a compact capture
as minimal if the OS does not offer the required layout.

## Screenshot matrix and assertions

The matrix is 6 states × 4 presentations × light/dark × Large/AX5 = 96
required case records per supported Dynamic Island host. Record unavailable
host presentations as unsupported with the device/OS reason; they are not
PASS and do not disappear from totals. An iPad or a non-Island phone can
exercise Lock Screen/banner content where the OS supports it, and must not
be claimed as Dynamic Island proof. The repository also has a Watch app;
this widget preparation does not prove its separate Watch controls or any
automatically mirrored Live Activity presentation.

| Fixture | Status text | Trailing/minimal symbol | Connection icon |
| --- | --- | --- | --- |
| disconnected | Waiting for glasses... | mic.slash, gray | disconnected |
| ready | Ready | mic.fill, green | connected |
| listening | Listening... | waveform, cyan | connected |
| processing | Thinking... | brain, orange | connected |
| speaking | Speaking... | speaker.wave.2.fill, cyan | connected |
| long-content | Speaking... | speaker.wave.2.fill, cyan | connected |

For each case save the full **system-hosted** screenshot, a crop for comparison
and a metadata record containing app/widget revision, Common pin, OS/device,
appearance, actual content-size category, presentation, fixture ID, activity
ID, capture time, result and image hash. File stem:
`live-activity-<presentation>-<fixture>-<light|dark>-<large|ax5>`.
Use the same device/OS and crop bounds when comparing before/after. Exclude
volatile clock/status-bar pixels explicitly; never mask content or controls.
Previews and UIHostingController/ImageRenderer captures help debugging but
cannot replace system-hosted screenshots or interactive evidence.

1. In Lock Screen content, assert the cyan background, readable status,
   correct connection indicator, expected state symbol and a single power
   control. Empty response renders `Bernard AI`; speaking renders the fixed
   sentence; long-content renders its bounded snippet without overlapping
   the power control. The current response line limit is one.
2. Expanded Island must show leading Glasses identity, trailing state symbol,
   bottom status, and response only when nonempty (current two-line limit).
   Assert no clipped glyphs, content under the sensor region, overlap or
   accidental extra control. Long response truncation is acceptable at its
   declared limit; disappearing status or controls is a failure.
3. Compact must show the glasses icon and expected trailing symbol; minimal
   must show the expected state symbol. Neither currently promises status
   text, a response or a power button. Check symbols stay inside system
   bounds and remain legible in both appearances.
4. At AX5 confirm the host's actual accessibility content-size category.
   Examine status/response fitting, control reachability and VoiceOver focus.
   Compact/minimal contain icons, so no larger text is expected there; they
   still require legible icons and meaningful accessible state. Fixed-size
   fonts in the baseline do not establish Dynamic Type support. Record
   clipping, missing spoken state or unusable hit targets as failures;
   screenshot similarity to baseline cannot turn these into PASS.
5. After Common publishes its widget role, compare power-control geometry,
   fill, pressed/disabled state and accessibility against that exact pinned
   role/contract. Do not bake the current app-local circle into an expected
   baseline. Before publication this shared-control assertion is BLOCKED.

## Interaction acceptance (real host required)

- On a dedicated test install with listening enabled, capture the Lock
  Screen control's accessibility name, hint, traits and hit frame. Require a
  discoverable stop/disable action and the approved Common hit-target policy
  once available; measure the real host's target, not the icon's visual size.
  Baseline source has no explicit accessibility label or target size, so
  discovery/target compliance is unverified.
- Activate the power action once. Verify actual listening/wake-word
  detection stops, app listening state becomes false, and the Live Activity
  ends. Capture before/action/after evidence with a bounded observation
  timeout recorded in metadata; no observed transition is FAIL, not retry
  until it disappears. Repeat with app running and with the app process
  terminated, including the next foreground. Use a dedicated production
  interaction pass; the minimal fixture host does not own AppState and
  cannot prove those effects.
- In expanded/compact/minimal, verify system tap/open and long-press/expand
  behavior without claiming a custom deep-link destination. Source declares
  no widgetURL or Link. Do not expect a disable button in these presentations.
- Keep screenshot sessions free of real microphone/camera/location/network
  services. Any production interaction pass needs its own scoped authority
  and dedicated test data, independent of this source preparation.

## Intent audit boundary

Both app and widget define `DisableListeningIntent`. The widget version
writes `UserDefaults.standard`; the app version additionally calls
`AppStateProvider.shared?.setListeningEnabled(false)`. The app entitlements
file currently has an empty dict, and the widget target has no declared App
Group entitlement. These facts raise a cross-process persistence hypothesis,
not proof of an intent failure: LiveActivityIntent runtime execution and
target selection must be observed on the real host. No App Group, backend,
preferences or intent behavior is changed in this task. Report a failed
interaction with process/target evidence before proposing a separate fix.
