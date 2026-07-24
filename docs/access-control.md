# Access Control — Internal-Only Distribution Proof (WO#620 · D4)

**Claim:** a person who is not an explicitly-authorized ForIT member **cannot install** ForIT Glasses
(`com.forit.openglasses.dolores`, ASC app `6761319043`).

This holds because there is **no non-member-accessible install surface at all**, and the only surface
that exists is gated to named Apple IDs. Verified via the App Store Connect API (read-only) on 2026-07-24.

## The three install surfaces Apple offers — and why each is closed to non-members

1. **Public App Store listing** — *does not exist.* The only App Store version ever created is `1.0`,
   state `REJECTED`. There is no released, downloadable public build. A non-member searching the App
   Store finds nothing to install.
2. **Unlisted / public TestFlight link** — *not enabled.* Neither beta group has a public link
   (`publicLinkEnabled = None` on both). There is no shareable URL that would let an arbitrary Apple ID
   join and install.
3. **TestFlight Internal groups** — *the only live channel, and membership is explicit.* The app has
   exactly two groups, **both internal** (`isInternalGroup = true`):
   - `ForIT Internal` (`971212a6-…`) — `hasAccessToAllBuilds=true` — testers: `me@bthomas.io`
   - `App Store Connect Users` (`dcdf189d-…`) — testers: `me@bthomas.io`

   Apple restricts internal-build access to (a) users on the ASC team and (b) Apple IDs explicitly added
   as internal testers. A non-member is neither, receives no invitation, and cannot see or install the
   build through TestFlight.

## Empirical state (verified, read-only)

- Distinct testers across **all** groups: **1** — `me@bthomas.io` (Benjamin Thomas). No external testers.
- Groups: **2, both internal.** No external group, no public link.
- Public App Store build: **none** (v1.0 REJECTED).

Because no public path exists (points 1 & 2) and the internal path is membership-gated to a single
named Apple ID (point 3), a non-member has **zero** route to install. The negative outcome is
deterministic — it does not depend on a particular device or attempt.

## On a live negative test

A live "outsider tries and fails" test would require a **second, non-member Apple ID** to attempt a
join/redeem and be refused. That is an outward, account-structural action and is **unnecessary** here:
with no public listing and no public link, there is no join/redeem entry point for a non-member to even
attempt. The guarantee rests on the *absence* of any public surface plus explicit-membership gating,
both verified above.

## Keeping it internal-only (operating rules)

- **Do not** enable a public TestFlight link on any group.
- **Do not** submit the app for public App Store release (the rejected v1.0 stays rejected).
- Add staff **only** as named internal testers to `ForIT Internal`. Removing a tester revokes access.
- For a managed/enforced posture (MDM, org-scoped install), see the ABM Custom App path in
  [`distribution-model.md`](./distribution-model.md).
