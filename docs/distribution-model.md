# Internal Distribution Model — Evaluation & Decision (WO#620 · D1)

**App:** ForIT Glasses (`com.forit.openglasses.dolores`) · ASC app `6761319043` · Team `UUSSWWML2A` (ForIT LLC)
**Goal:** distribute the app to ForIT staff *privately* — no public App Store listing — as a **properly, repeatably internally-distributed** app.

## TL;DR recommendation

**Stay on TestFlight *Internal* distribution** (the "ForIT Internal" group) as the end-state for now.
It is the correct, zero-marginal-cost, no-review way to get the app onto ≤100 ForIT staff devices privately.
Its **only** real drawback — TestFlight builds expire 90 days after upload (this is why builds 10–17 all
went dead) — is now **automated away by CI**: any push re-cuts a fresh build, and we can add a scheduled
re-cut so a current build always exists.

**Graduate to an ABM Custom App only if** Ben later needs *either*:
1. **No-expiry permanent installs** without relying on CI re-cutting every ≤90 days, **or**
2. **Silent MDM push** to managed devices (e.g. via Jamf) instead of staff self-installing from the TestFlight app.

**Reject the Apple Developer Enterprise Program** — $299/yr (money gate), requires 100+ employees, and is
actively discouraged by Apple. Not viable here.

## Options compared (2025 facts)

| Method | Cost beyond current | Private? | Build expiry | App Review | Install UX | MDM push |
|---|---|---|---|---|---|---|
| **TestFlight Internal** ← *current* | none ($99 program already held) | Yes — ≤100 named staff | **90 days/build** | **None** for internal | TestFlight app, tap Install | No |
| **ABM Custom App** | ABM enrollment (free, needs D‑U‑N‑S) | Yes — org-scoped | **None (permanent)** | **Every version** (private Custom Apps review) | MDM or redeem code | **Yes** (Jamf/Intune) |
| **Unlisted App** | none | Weak — anyone with link | None | Every version + unlisted approval | Public App Store link | No |
| **Enterprise Program** | **+$299/yr** | Yes — internal | None | None | Manual/MDM | Yes |

Sources: Apple *App build statuses* + *Distribute proprietary in-house apps* deployment guide; Foresight Mobile
"Complete iOS App Distribution Guide 2025". 90-day internal expiry corroborated empirically — builds 10–17
(uploaded 2026‑04‑10..12) all show `expired=true` in the ASC API.

## Why TestFlight Internal is the right first end-state

- **Zero new cost, zero review, zero new enrollment.** Uses the existing ForIT LLC program + signing that's
  already valid to 2027. No money gate touched.
- **Genuinely private.** Internal testers are explicitly named Apple IDs in the "ForIT Internal" group — a
  non-member cannot install (see D4). No public listing exists (the old public v1.0 submission was rejected
  and we are *not* pursuing it).
- **The expiry problem is now an automation problem, and it's solved.** The hardened CI pipeline
  (`.github/workflows/build-and-upload.yml`) computes the build number from *ASC latest + 1*, archives,
  uploads, and auto-clears export compliance. Because "ForIT Internal" is an internal group with
  `hasAccessToAllBuilds=true`, every uploaded build is exposed to its testers automatically — no explicit
  build→group assignment is needed (App Store Connect actually *rejects* one with 422 "Cannot add internal
  group to a build"). So a fresh, installable build is one push away, and a scheduled monthly run would keep
  a non-expired build live indefinitely.

## What the ABM Custom App path would cost (if chosen later)

- **Enroll ForIT in Apple Business Manager** (free; requires the company D‑U‑N‑S number and a verification
  call). One-time. — *This is an outward / account-structural step: surface to Ben/Commander before doing it.*
- **Set the app's distribution to "Private" + list ForIT's Organization ID**, then submit for **Custom Apps
  review** on every version (build-only bumps still bypass review, like TestFlight).
- **Deploy** either by redeem code or, if ForIT runs **Jamf/Intune**, silent managed push to enrolled devices.
- Buys: permanent (non-expiring) installs + silent MDM deployment. Costs: ABM setup + a review gate per version.

## Decision needed from Ben / Commander

> Is TestFlight-Internal (with CI auto-recut) sufficient, or do you want the ABM Custom App upgrade for
> no-expiry + Jamf push? The latter needs a **free ABM enrollment** (D‑U‑N‑S + verification) — no money, but
> it's an outward account action I will not take without a go-ahead.

Default if no answer: **keep TestFlight Internal** and add a scheduled monthly CI re-cut so a live build always exists.
