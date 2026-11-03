# Preserved OpenGlasses simulator

The old iPhone simulator is retained for the failed first-boot investigation.
Its existing data stays with `ci-OpenGlasses-iPhoneOld`, device
`A5E302B9-7202-4C2C-BE4B-B2B7D0DD3CD4`. The working primary iPhone remains
`A86BCF14-B009-4600-BB0B-B96341D39170`. Booting the old phone does not require
changing the primary mapping, erasing either phone or making another app release.

Dispatch's November 3 instruction routes this boot through the repository's
Mini runner with `forit-build-submit`. The manual workflow
`.github/workflows/forit-macos-simulator.yml` uses the installed lane helper with
the old device's exact identifier. The helper checks ownership, obtains the
normal boot admission and waits for boot readiness. It records the boot result,
always attempts to shut down only the old phone, then records the final primary
mapping and the lane's device list, including on failure. Runner logs
are the evidence of the attempt; the presence of this workflow is not proof of
a successful boot.

The job allows 90 minutes for normal admission, first-boot migration and
cleanup. The caller's first-boot allowance is 20 minutes; the installed gate
keeps its own limits. These budgets do not guarantee migration succeeds. If
shutdown returns an error because the phone was already shut down, use the
final device list to establish its state; do not treat a failed boot as success.

Before the first dispatch, for-dev must qualify a repository-eligible Mini
runner, and OpenGlasses must register the new manual workflow on the default branch. A feature
branch containing a new manual workflow alone does not satisfy GitHub's
[default-branch requirement](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
Once both prerequisites are met, submit exactly one run:

```sh
forit-build-submit --apple --repo ForITLLC/OpenGlasses \
  --ref BTForIT/openglasses-shared-mark-topbar \
  --workflow forit-macos-simulator.yml --wait --timeout 5400
```

If submission or monitoring fails, read the existing run's status and logs
before retrying. Do not substitute a direct SSH boot, another product's runner
or a GitHub-hosted Mac. The App Store review workflow is unrelated to this task.
