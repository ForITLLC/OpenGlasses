# Copied from ForITLLC/for-Notes apps/ios/Scripts/asc_attach.py at f77e50a335343b0bcea4587fabd2614513595519
"""After the upload, wait for App Store Connect to finish processing the build, answer its export
compliance and make it visible to the internal TestFlight group.

Adapted to OpenGlasses (ForIT Glasses, App Store Connect app 6761319043). What changed from for-Notes:
  - iPhone (IOS) builds only: the --platform option and the visionOS / Mac choices are dropped. The
    lookup still filters on the IOS platform.
  - Export compliance: once the build is VALID and App Store Connect has no answer for it yet, this
    sets usesNonExemptEncryption=false, as .github/workflows/build-and-upload.yml did ("Clear export
    compliance"). OpenGlasses/Info.plist has no ITSAppUsesNonExemptEncryption key, so without this
    TestFlight holds every build at "Missing Compliance". An answer already on the build is left alone.

The upload alone does not make a build visible to testers: a beta group with
hasAccessToAllBuilds=false only sees builds attached through the API. "ForIT Internal" is an
internal group WITH access to all builds: it sees every build once processing finishes, and App
Store Connect refuses the attach for such a group with HTTP 422. So the group is looked up first
and the attach is skipped when there is nothing to attach.

--require-valid makes a build that is not VALID in time a red step instead of a warning (the
workflow failed the same way), and prints the VALID build's internal TestFlight state
(buildBetaDetail.internalBuildState, IN_BETA_TESTING once internal testers have it).

--whats-new sets the build's "What to Test" text once it is VALID. Internal testing only: nothing
here makes an external group or a public link, or submits anything for review.

Pure logic takes an injected `api` callable and clock.

Usage (env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_BASE64):
  asc_attach.py --app-id <id> --group-id <id> --version <CFBundleVersion>
                [--whats-new "<text>"] [--require-valid]
"""
from __future__ import annotations

import argparse
import base64
import os
import sys
import time
from typing import Callable, Optional

import asc_resolve

Api = Callable[..., dict]
LOCALE = "en-US"
PLATFORM = "IOS"


def wait_for_build(api: Api, app_id: str, version: str, platform: str = PLATFORM, *,
                   now: Callable[[], float], sleep: Callable[[float], None],
                   poll: float = 30, timeout: float = 1200) -> Optional[str]:
    """The id of the VALID build for this version on this platform, or None when the
    build is INVALID or not processed before the deadline."""
    deadline = now() + timeout
    path = (f"/builds?filter[app]={app_id}&filter[version]={version}"
            f"&filter[preReleaseVersion.platform]={platform}&sort=-uploadedDate")
    while True:
        builds = api("GET", path).get("data", [])
        if builds:
            b = builds[0]
            state = b["attributes"]["processingState"]
            print(f"found build {b['id']} version={version} platform={platform} state={state}")
            if state == "VALID":
                return b["id"]
            if state == "INVALID":
                print("::warning::build INVALID — not attaching to TestFlight group")
                return None
        else:
            print(f"build version={version} platform={platform} not visible in ASC yet, waiting...")
        if now() + poll >= deadline:
            return None
        sleep(poll)


def ensure_compliance(api: Api, build_id: str) -> str:
    """Answer export compliance (no non-exempt encryption) when the build has no answer yet."""
    attrs = api("GET", f"/builds/{build_id}?fields[builds]=usesNonExemptEncryption").get("data", {}).get(
        "attributes", {})
    current = attrs.get("usesNonExemptEncryption")
    if current is not None:
        return f"export compliance already answered on build {build_id} (usesNonExemptEncryption={current})"
    api("PATCH", f"/builds/{build_id}", body={"data": {
        "type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False},
    }})
    return f"export compliance set on build {build_id}: usesNonExemptEncryption=false"


def group_sees_all_builds(api: Api, group_id: str) -> bool:
    """True for an internal group with access to all builds: every build is visible to
    it already, and App Store Connect refuses the attach POST for it (422)."""
    attrs = api("GET", f"/betaGroups/{group_id}").get("data", {}).get("attributes", {})
    return bool(attrs.get("isInternalGroup") and attrs.get("hasAccessToAllBuilds"))


def attach(api: Api, group_id: str, build_id: str) -> str:
    """Make the build visible to the group. Returns the line to print."""
    if group_sees_all_builds(api, group_id):
        return (f"beta group {group_id} is an internal group with access to all builds — "
                f"build {build_id} is visible to it already; nothing to attach")
    api("POST", f"/betaGroups/{group_id}/relationships/builds",
        body={"data": [{"type": "builds", "id": build_id}]})
    return f"attached build {build_id} to beta group {group_id}"


def ensure_whats_new(api: Api, build_id: str, whats_new: str) -> str:
    """The build's "What to Test" (its en-US beta build localization). Idempotent."""
    rows = api("GET", f"/builds/{build_id}/betaBuildLocalizations").get("data", [])
    current = next((r for r in rows if r["attributes"].get("locale") == LOCALE), None)
    if current is None:
        api("POST", "/betaBuildLocalizations", body={"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": LOCALE, "whatsNew": whats_new},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }})
        return "set what to test on the build"
    if current["attributes"].get("whatsNew") == whats_new:
        return "what to test already set on the build"
    api("PATCH", f"/betaBuildLocalizations/{current['id']}", body={"data": {
        "type": "betaBuildLocalizations", "id": current["id"], "attributes": {"whatsNew": whats_new},
    }})
    return "updated what to test on the build"


def internal_state(api: Api, build_id: str) -> str:
    """The build's internal TestFlight state, e.g. IN_BETA_TESTING."""
    attrs = api("GET", f"/builds/{build_id}/buildBetaDetail").get("data", {}).get("attributes", {})
    return attrs.get("internalBuildState") or "unknown"


def run(api: Api, app_id: str, group_id: str, version: str, *,
        now: Callable[[], float], sleep: Callable[[float], None], whats_new: str = "",
        require_valid: bool = False) -> int:
    build_id = wait_for_build(api, app_id, version, now=now, sleep=sleep)
    if not build_id:
        if require_valid:
            print(f"::error title=Build not VALID::build {version} ({PLATFORM}) is not VALID in App Store Connect")
            return 1
        print("::warning::could not attach build to TestFlight group (not VALID within timeout) — attach manually")
        return 0
    try:
        print(ensure_compliance(api, build_id))
    except asc_resolve.AscError as e:
        # The workflow printed this and went on; testers see the build once someone answers it.
        print(f"::warning::could not set export compliance on build {build_id} (HTTP {e.status}): {e.detail}")
    if whats_new.strip():
        try:
            print(ensure_whats_new(api, build_id, whats_new.strip()))
        except asc_resolve.AscError as e:
            # Testers can still install the build; only the text is missing.
            print(f"::warning::could not set What to Test on build {build_id} (HTTP {e.status}): {e.detail}")
    try:
        print(f"{attach(api, group_id, build_id)} (version={version}, {PLATFORM})")
    except asc_resolve.AscError as e:
        if e.status != 422:
            raise  # auth, transport, Apple outage: fail the step so someone looks
        # 422 is App Store Connect saying this link is not allowed for this group.
        # The build is not lost — it is in ASC, VALID — so warn and keep the run green.
        print(f"::warning::App Store Connect refused to attach build {build_id} to beta group "
              f"{group_id} (HTTP 422): {e.detail}")
    if require_valid:
        print(f"build {build_id} ({PLATFORM}) internal testing: {internal_state(api, build_id)}")
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--app-id", required=True)
    ap.add_argument("--group-id", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--whats-new", default="", help="the build's What to Test text (en-US)")
    ap.add_argument("--require-valid", action="store_true",
                    help="fail when the build is not VALID in time, and print its internal TestFlight state")
    args = ap.parse_args(argv)

    private_key = base64.b64decode(os.environ["ASC_KEY_BASE64"]).decode()
    api = asc_resolve.make_api(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], private_key)
    return run(api, args.app_id, args.group_id, args.version, now=time.time, sleep=time.sleep,
               whats_new=args.whats_new, require_valid=args.require_valid)


if __name__ == "__main__":
    sys.exit(main())
