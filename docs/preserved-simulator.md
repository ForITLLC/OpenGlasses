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
normal boot admission and waits for boot readiness. The final step records the
primary mapping and the lane's device list, including on failure. Runner logs
are the evidence of the attempt; the presence of this workflow is not proof of
a successful boot.

Before the first dispatch, for-dev must qualify a repository-eligible Mini
runner and register the new manual workflow on the default branch. A feature
branch containing a new manual workflow alone does not satisfy GitHub's
[default-branch requirement](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
Once both prerequisites are met, submit exactly one run:

```sh
forit-build-submit --apple --repo ForITLLC/OpenGlasses \
  --ref BTForIT/openglasses-shared-mark-topbar \
  --workflow forit-macos-simulator.yml --wait
```

If submission or monitoring fails, read the existing run's status and logs
before retrying. Do not substitute a direct SSH boot, another product's runner
or a GitHub-hosted Mac. The App Store review workflow is unrelated to this task.
