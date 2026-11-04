# OpenGlasses simulator checks

The working primary iPhone is `ci-OpenGlasses-iPhone`, device
`A86BCF14-B009-4600-BB0B-B96341D39170`. The original phone and its existing data
remain preserved as `ci-OpenGlasses-iPhoneOld`, device
`A5E302B9-7202-4C2C-BE4B-B2B7D0DD3CD4`. The current owner choice is to use the
working phone for the manual check and preserve the original without another
boot attempt as part of this correction. Neither phone needs erasing or remapping.
A simulator check does not require another app release; the build 35 release
evidence remains tied to source `7e19f3f2175067aa8b3f0d6aa9fa7503b9bd480b`.

Dispatch's November 3 instruction routes manual checks through the repository's
Mini runner with `forit-build-submit`. The manual workflow
`.github/workflows/forit-macos-simulator.yml` now uses the installed
`/Users/Shared/ci-sim/ci-sim-lane.sh --lane OpenGlasses` helper with the working
phone's exact A86 identifier. The helper checks ownership, obtains normal boot
admission and waits for boot readiness. The workflow records the boot result,
always attempts to shut down that same working phone, then records the final
primary mapping and the lane's device list, including on failure. Runner logs
are the evidence of an attempt; this workflow edit is not proof of a successful
working-phone check.

The job allows 90 minutes for normal admission, first-boot migration and
cleanup. The caller's first-boot allowance is 20 minutes; the installed gate
keeps its own limits. These budgets do not guarantee migration succeeds. If
shutdown returns an error because the phone was already shut down, use the
final device list to establish its state; do not treat a failed boot as success.

The route requires a repository-eligible Mini runner qualified by for-dev and
the manual workflow registered on the default branch. A feature branch
containing a new manual workflow alone does not satisfy GitHub's
[default-branch requirement](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
For a future authorized working-phone check, once both prerequisites are met,
submit exactly one run from `main`:

```sh
forit-build-submit --apple --repo ForITLLC/OpenGlasses \
  --ref main \
  --workflow forit-macos-simulator.yml --wait --timeout 5400
```

If submission or monitoring fails, read the existing run's status and logs
before retrying. Do not substitute a direct SSH boot, another product's runner
or a GitHub-hosted Mac. The App Store review workflow is unrelated to this task.

## Completed original-phone attempt

The separately authorized [original phone run](https://github.com/ForITLLC/OpenGlasses/actions/runs/41648686103)
used source `85c588762bf5d5bc8d93e410020c7a4e239b18a2` on November 3. After
1514 seconds of normal gate waiting, A5 was admitted and reached the simulator's
Booted state at 14:20:41 UTC. Its boot-status wait reached the 1200-second limit
at 14:40:41 UTC, and the helper reported that runtime data migration had not
finished. The job completed with failure at 14:40:53 UTC; Booted state did not
establish successful migration or readiness.

The always-run shutdown succeeded. The final device list showed A5 Shutdown
under its original name, with A86 still the primary iPhone. The helper left the
reported nonempty shared WAL unchanged; this observation does not establish the
cause of the migration failure or prove every data file's integrity. for-dev
owns any separate Mini migration diagnosis. This completed attempt is retained
as evidence, not repeated by the working-phone workflow correction.
